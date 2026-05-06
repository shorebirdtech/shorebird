import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:shorebird_code_push/src/generated/updater_bindings.g.dart';
import 'package:shorebird_code_push/src/shorebird_updater_io.dart';
import 'package:shorebird_code_push/src/updater.dart';

import '../generated/test_hooks_bindings.g.dart';
import 'fake_patch_server.dart';

/// Stand-in for the Flutter engine in integration tests.
///
/// In production the engine is what loads `libupdater`, calls
/// `shorebird_init` at startup, and reports launch outcomes back to the
/// updater. None of that is visible at the Dart level. This class
/// concentrates everything an integration test needs to drive that
/// engine-side behavior into one place, so test bodies stay focused on
/// the public `ShorebirdUpdater` API.
class TestEngine {
  TestEngine._(this._bindings, this._cdylibPath);

  /// Loads the test_hooks cdylib, wires it into `shorebird_code_push`'s
  /// `Updater.bindings` test seam, and returns a `TestEngine` ready to
  /// drive scenarios. The path is retained so per-isolate FFI calls
  /// (see [createUpdater]) can re-open the same library.
  factory TestEngine.setup(String cdylibPath) {
    final lib = DynamicLibrary.open(cdylibPath);
    Updater.bindings = UpdaterBindings(lib);
    return TestEngine._(TestHooksBindings(lib), cdylibPath);
  }

  final TestHooksBindings _bindings;
  final String _cdylibPath;

  /// Initializes the updater for a single test. Acts as the engine
  /// would on app startup: configures storage paths, the release
  /// version, and the `shorebird.yaml` (synthesized here from
  /// `app_id` + the test's [server] base URL).
  ///
  /// [libappBase] is written to `libapp_path` before init. On
  /// non-test desktop builds, `patch_base` (in
  /// `library/src/updater.rs`) reads that file directly when applying
  /// a patch — the Android `cfg(test)` path that uses an apk doesn't
  /// run in our non-`cfg(test)` cdylib. Tests that install a patch
  /// must pass the patch fixture's `base` bytes here. Tests that
  /// don't install a patch can leave it as the default empty slice.
  void init({
    required Directory tmp,
    required FakePatchServer server,
    Uint8List? libappBase,
    String releaseVersion = '1.0.0',
  }) {
    final storage = '${tmp.path}/storage';
    final cache = '${tmp.path}/cache';
    Directory(storage).createSync();
    Directory(cache).createSync();
    final libapp = '${tmp.path}/lib/arm64/libapp.so';
    final libappFile = File(libapp);
    libappFile.parent.createSync(recursive: true);
    libappFile.writeAsBytesSync(libappBase ?? Uint8List(0));
    final yaml = 'app_id: test_app\nbase_url: ${server.baseUrl}';

    final pStorage = storage.toNativeUtf8();
    final pCache = cache.toNativeUtf8();
    final pRelease = releaseVersion.toNativeUtf8();
    final pLibapp = libapp.toNativeUtf8();
    final pYaml = yaml.toNativeUtf8();
    try {
      final ok = _bindings.shorebird_test_init(
        pStorage.cast(),
        pCache.cast(),
        pRelease.cast(),
        pLibapp.cast(),
        pYaml.cast(),
      );
      if (!ok) {
        throw StateError('shorebird_test_init returned false');
      }
    } finally {
      // shorebird_test_init copies the strings via to_rust(), so
      // freeing here is safe.
      malloc
        ..free(pStorage)
        ..free(pCache)
        ..free(pRelease)
        ..free(pLibapp)
        ..free(pYaml);
    }
  }

  /// Resets all global updater state. Equivalent to a fresh process
  /// boot — call between tests.
  void reset() => _bindings.shorebird_test_reset();

  /// Simulates the engine's successful boot of `next_boot_patch`. In
  /// production the engine does this internally after Dart VM startup
  /// completes; the Dart layer never observes the underlying protocol.
  void simulateSuccessfulLaunch() =>
      _bindings.shorebird_test_simulate_successful_launch();

  /// Builds a [ShorebirdUpdater] suitable for tests.
  ///
  /// FFI calls run in a sub-isolate via `Isolate.run` (the same dispatch
  /// production uses) so they don't block the main isolate's event loop —
  /// the [FakePatchServer] runs there and would otherwise deadlock with
  /// the synchronous `ureq` HTTP request inside the FFI call.
  ///
  /// Each sub-isolate re-opens the cdylib (cheap: `dlopen` is ref-counted
  /// against the already-loaded image) and sets `Updater.bindings`,
  /// because Dart isolates do not share static fields. The override the
  /// main isolate did in [TestEngine.setup] doesn't propagate.
  ShorebirdUpdater createUpdater() {
    final path = _cdylibPath;
    return ShorebirdUpdaterImpl(
      run: <R>(FutureOr<R> Function() computation, {String? debugName}) {
        return Isolate.run<R>(() async {
          Updater.bindings = UpdaterBindings(DynamicLibrary.open(path));
          return computation();
        });
      },
    );
  }
}

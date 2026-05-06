// All updater integration tests live in this single file. This is
// deliberate: `package:test` parallelizes tests across files via
// isolates, but `dlopen` loads the test_hooks cdylib exactly once per
// process and the updater's `OnceCell<UpdateConfig>` is shared across
// every isolate. Splitting these tests across multiple files would
// require either a `dart_test.yaml` concurrency override scoped to
// `test/integration/`, or a subprocess-per-test runner.
//
// Same file = same isolate = serial = no contention. If the suite
// outgrows one file, see `docs/integration_tests.md` for the
// concurrency-override path.
//
// The unit tests under `test/src/` are unaffected: they only use
// `_MockUpdaterBindings` and never load the real cdylib.

// `setUpAll` shells out to `cargo build -p library_test_hooks`. On a
// cold checkout that compiles `updater` and its dependencies and can
// take a couple of minutes — well past `package:test`'s default 30s
// per-test timeout, which also covers `setUpAll`.
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:test/test.dart';

import 'helpers/build.dart';
import 'helpers/fake_patch_server.dart';
import 'helpers/fixtures.dart';
import 'helpers/test_engine.dart';

void main() {
  // Set in setUpAll exactly when the cdylib build/load failed. The
  // pair (`skipReason`, `engine`) is contractually mutually exclusive:
  // a null `skipReason` means `engine` is initialized, and tests
  // early-return on a non-null `skipReason` before touching `engine`.
  String? skipReason;
  late final TestEngine engine;

  setUpAll(() async {
    try {
      final path = await buildTestHooksCdylib();
      engine = TestEngine.setup(path);
    } on Object catch (e, st) {
      skipReason = 'Could not build/load library_test_hooks cdylib.\n$e\n$st';
    }
  });

  group('updater integration', () {
    late Directory tmp;
    late FakePatchServer server;

    setUp(() async {
      if (skipReason != null) return;
      // Single shared process: each test starts from a clean updater +
      // fresh tempdir + fresh fake server.
      engine.reset();
      tmp = Directory.systemTemp.createTempSync('updater-it-');
      server = await FakePatchServer.start();
    });

    tearDown(() async {
      if (skipReason != null) return;
      await server.stop();
      tmp.deleteSync(recursive: true);
    });

    test('checkForUpdate returns upToDate when server has no patch', () async {
      // `markTestSkipped` only flags the test as skipped — it does
      // not abort execution. Early-return after marking, otherwise
      // the body below would touch the uninitialized `engine` when
      // setUpAll could not build the cdylib (e.g., no Rust toolchain
      // on the host).
      final reason = skipReason;
      if (reason != null) {
        markTestSkipped(reason);
        return;
      }

      server.respondWithNoUpdate();
      engine.init(tmp: tmp, server: server);

      final updater = engine.createUpdater();
      expect(await updater.checkForUpdate(), UpdateStatus.upToDate);
      expect(await updater.readCurrentPatch(), isNull);
      expect(await updater.readNextPatch(), isNull);
      expect(server.patchCheckCount, 1);
      expect(server.downloadCount, 0);
    });

    test('install a patch and boot from it', () async {
      final reason = skipReason;
      if (reason != null) {
        markTestSkipped(reason);
        return;
      }

      server.enqueuePatch(helloTestsPatch);
      engine.init(
        tmp: tmp,
        server: server,
        libappBase: helloTestsPatch.base,
      );

      final updater = engine.createUpdater();

      // Initial state: no patch, but server has one available.
      expect(await updater.checkForUpdate(), UpdateStatus.outdated);
      expect(await updater.readCurrentPatch(), isNull);
      expect(await updater.readNextPatch(), isNull);

      // Apply it. update() should complete without throwing.
      await updater.update();

      // Patch is staged but the running session hasn't booted it.
      expect(await updater.checkForUpdate(), UpdateStatus.restartRequired);
      expect(await updater.readCurrentPatch(), isNull);
      expect(
        (await updater.readNextPatch())?.number,
        helloTestsPatch.number,
      );

      // Engine boots the new patch.
      engine.simulateSuccessfulLaunch();

      // Server still has patch 1 enqueued, but the updater knows it's
      // already installed (`should_install_patch` returns
      // PatchAlreadyInstalled), so checkForUpdate reports upToDate.
      expect(await updater.checkForUpdate(), UpdateStatus.upToDate);
      expect(
        (await updater.readCurrentPatch())?.number,
        helloTestsPatch.number,
      );
      expect(
        (await updater.readNextPatch())?.number,
        helloTestsPatch.number,
      );
      expect(server.downloadCount, 1);
    });

    // Regression for shorebirdtech/shorebird#3728 (and originally
    // #3206). Pre-fix, after a patch-to-release rollback the
    // updater's `current_boot_patch_number` would silently flip to 0
    // because `try_fall_back_from_patch` cleared `last_booted_patch`
    // for the patch the process was actually executing. The Dart
    // layer compared `null != null` and reported `upToDate`, leaving
    // callers no signal to prompt a restart. This test would have
    // caught it.
    test(
        'checkForUpdate returns restartRequired after patch-to-release '
        'rollback', () async {
      final reason = skipReason;
      if (reason != null) {
        markTestSkipped(reason);
        return;
      }

      // Phase 1: install + launch patch 1.
      server.enqueuePatch(helloTestsPatch);
      engine.init(
        tmp: tmp,
        server: server,
        libappBase: helloTestsPatch.base,
      );
      final updater = engine.createUpdater();
      await updater.update();
      engine.simulateSuccessfulLaunch();
      expect(
        (await updater.readCurrentPatch())?.number,
        helloTestsPatch.number,
      );

      // Phase 2: server rolls patch 1 back with no replacement.
      server.respondWithRollback([helloTestsPatch.number]);

      // Pre-fix: this returned upToDate. Post-fix: restartRequired —
      // the running process is on patch 1 but the next boot will
      // fall back to the base release.
      expect(await updater.checkForUpdate(), UpdateStatus.restartRequired);
      // current_boot_patch_number must keep reporting patch 1 — the
      // process is still executing it.
      expect(
        (await updater.readCurrentPatch())?.number,
        helloTestsPatch.number,
      );
      // next_boot_patch was cleared by the rollback.
      expect(await updater.readNextPatch(), isNull);
    });
  });
}

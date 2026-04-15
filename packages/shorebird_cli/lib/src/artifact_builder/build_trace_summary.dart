import 'dart:convert';
import 'dart:io';

/// A privacy-safe summary of a Chrome Trace Event Format build trace.
///
/// Contains only aggregate millisecond timings and small integer counters —
/// no target names, file paths, user identifiers, or other free-form fields
/// that could identify the project. This is the data we're willing to upload
/// to Shorebird servers to understand slow builds in the wild.
class BuildTraceSummary {
  /// {@macro build_trace_summary}
  BuildTraceSummary({
    required this.platform,
    required this.flutterBuildMs,
    required this.flutterToolMs,
    required this.nativeBuildMs,
    required this.kernelSnapshotMs,
    required this.genSnapshotMs,
    required this.dartBuildMs,
    required this.assetsMs,
    required this.codegenMs,
    required this.otherAssembleMs,
    required this.assembleTargetCount,
    required this.skippedAssembleTargetCount,
    this.shorebirdOverheadMs,
  });

  /// Build a summary from the raw list of trace events written by Flutter.
  ///
  /// [events] is the top-level list in the Chrome Trace Event Format file.
  /// [platform] is a short tag identifying the build (e.g. `android`, `ios`).
  /// [shorebirdOverhead] captures Shorebird's own wall-clock time around the
  /// `flutter build` invocation (everything the CLI does before/after Flutter
  /// runs). When null, the summary reports Flutter-side numbers only.
  factory BuildTraceSummary.fromEvents(
    List<Map<String, Object?>> events, {
    required String platform,
    Duration? shorebirdOverhead,
  }) {
    var flutterBuildUs = 0;
    var flutterToolUs = 0;
    var nativeBuildUs = 0;
    var kernelSnapshotUs = 0;
    var genSnapshotUs = 0;
    var dartBuildUs = 0;
    var assetsUs = 0;
    var codegenUs = 0;
    var otherAssembleUs = 0;
    var assembleCount = 0;
    var skippedCount = 0;

    for (final e in events) {
      final dur = (e['dur'] as num?)?.toInt() ?? 0;
      final tid = (e['tid'] as num?)?.toInt() ?? 0;
      final name = (e['name'] as String?) ?? '';
      final args = (e['args'] as Map?) ?? const {};
      final skipped = args['skipped'] == true;

      // Per PR 116: tid 1 = flutter tool, tid 2 = native build system
      // (gradle/xcode), tid 3 = flutter assemble targets.
      if (tid == 1) {
        if (name.startsWith('flutter build ')) {
          flutterBuildUs = dur;
        } else {
          flutterToolUs += dur;
        }
      } else if (tid == 2) {
        nativeBuildUs += dur;
      } else if (tid == 3) {
        assembleCount++;
        if (skipped) skippedCount++;
        switch (_categorize(name)) {
          case _AssembleCategory.kernelSnapshot:
            kernelSnapshotUs += dur;
          case _AssembleCategory.genSnapshot:
            genSnapshotUs += dur;
          case _AssembleCategory.dartBuild:
            dartBuildUs += dur;
          case _AssembleCategory.assets:
            assetsUs += dur;
          case _AssembleCategory.codegen:
            codegenUs += dur;
          case _AssembleCategory.other:
            otherAssembleUs += dur;
        }
      }
    }

    return BuildTraceSummary(
      platform: platform,
      flutterBuildMs: flutterBuildUs ~/ 1000,
      flutterToolMs: flutterToolUs ~/ 1000,
      nativeBuildMs: nativeBuildUs ~/ 1000,
      kernelSnapshotMs: kernelSnapshotUs ~/ 1000,
      genSnapshotMs: genSnapshotUs ~/ 1000,
      dartBuildMs: dartBuildUs ~/ 1000,
      assetsMs: assetsUs ~/ 1000,
      codegenMs: codegenUs ~/ 1000,
      otherAssembleMs: otherAssembleUs ~/ 1000,
      assembleTargetCount: assembleCount,
      skippedAssembleTargetCount: skippedCount,
      shorebirdOverheadMs: shorebirdOverhead?.inMilliseconds,
    );
  }

  /// Parse [traceFile] and return a summary, or null if the file is missing
  /// or can't be parsed as a Chrome Trace Event Format JSON array.
  static BuildTraceSummary? tryFromFile(
    File traceFile, {
    required String platform,
    Duration? shorebirdOverhead,
  }) {
    if (!traceFile.existsSync()) return null;
    try {
      final decoded = jsonDecode(traceFile.readAsStringSync());
      final list = decoded is List
          ? decoded
          : (decoded is Map ? decoded['traceEvents'] as List? : null);
      if (list == null) return null;
      final events = list.cast<Map<String, Object?>>();
      return BuildTraceSummary.fromEvents(
        events,
        platform: platform,
        shorebirdOverhead: shorebirdOverhead,
      );
    } on FormatException {
      return null;
    }
  }

  static _AssembleCategory _categorize(String name) {
    final n = name.toLowerCase();
    // Dart frontend: source → kernel (.dill).
    if (n.contains('kernel_snapshot') || n == 'kernel') {
      return _AssembleCategory.kernelSnapshot;
    }
    // AOT via gen_snapshot: kernel → native code. Covers Android per-arch
    // targets, iOS `ios_aot`, and the older `aot_elf_*` / `aot_assembly_*`.
    if (n.startsWith('android_aot') ||
        n.contains('aot_assembly') ||
        n.contains('aot_elf') ||
        n == 'ios_aot' ||
        n.contains('aot_bundle')) {
      return _AssembleCategory.genSnapshot;
    }
    // Dart build scripts (`dart_build`) — user-authored build-time code
    // execution. Kept separate from codegen since it can dominate (~10s on
    // plugin-heavy apps) and is semantically "run Dart code", not "compile".
    if (n == 'dart_build') {
      return _AssembleCategory.dartBuild;
    }
    // Code generation: gen_dart_plugin_registrant, gen_localizations, etc.
    if (n.startsWith('gen_')) {
      return _AssembleCategory.codegen;
    }
    // Asset bundling and framework unpacking (copies prebuilt artifacts,
    // not compilation).
    if (n.contains('asset_bundle') ||
        n.contains('bundle_flutter_assets') ||
        n.contains('install_code_assets') ||
        n.contains('unpack') ||
        n.contains('copy_framework') ||
        n.contains('asset')) {
      return _AssembleCategory.assets;
    }
    return _AssembleCategory.other;
  }

  /// Short tag identifying the build (e.g. `android`, `ios`).
  final String platform;

  /// Flutter's own reported wall-clock duration (the "flutter build apk/ipa"
  /// umbrella event in the trace), in milliseconds.
  final int flutterBuildMs;

  /// Time spent in the flutter tool itself (pre/post-gradle setup), excluding
  /// the umbrella "flutter build X" span.
  final int flutterToolMs;

  /// Gradle (Android) or Xcode (iOS) outer span duration.
  final int nativeBuildMs;

  /// Dart frontend compilation (source → kernel).
  final int kernelSnapshotMs;

  /// gen_snapshot AOT compilation (kernel → native code), summed across
  /// architectures.
  final int genSnapshotMs;

  /// Time spent running user-authored Dart build scripts (the `dart_build`
  /// assemble target). Distinct from `genSnapshot` compilation of app code.
  final int dartBuildMs;

  /// Asset bundling and copying.
  final int assetsMs;

  /// Code-generation targets (plugin registrant, localizations, etc.).
  final int codegenMs;

  /// Any flutter assemble target that didn't fit the categories above.
  final int otherAssembleMs;

  /// Number of flutter assemble targets that ran during the build.
  final int assembleTargetCount;

  /// Number of those targets that were cache hits.
  final int skippedAssembleTargetCount;

  /// Wall-clock time the Shorebird CLI spent around Flutter — everything
  /// except the time Flutter itself reports. Null if the caller couldn't
  /// compute it.
  final int? shorebirdOverheadMs;

  /// Dart-compile total (kernel snapshot + gen_snapshot). `dartBuildMs`
  /// (build-time Dart script execution) is tracked separately.
  int get dartMs => kernelSnapshotMs + genSnapshotMs;

  /// Approximate time the native toolchain (Gradle/Xcode) spent on native
  /// compilation, excluding the Flutter assemble sub-invocation that runs
  /// inside it. This is the clearest upper-bound for "time a Flutter-aware
  /// native build cache could save" — plugin AARs, pod compilation, Swift/
  /// Kotlin/ObjC/Java builds, linking, dex/app packaging.
  ///
  /// Computed as `nativeBuildMs - (sum of all flutter assemble target
  /// durations)`, clamped at 0. Not perfect (Xcode/Gradle can run flutter
  /// assemble and native compile in parallel on multi-core machines) but
  /// useful as an order-of-magnitude signal.
  int get nativeCompileMs {
    final assembleTotal =
        kernelSnapshotMs +
        genSnapshotMs +
        dartBuildMs +
        assetsMs +
        codegenMs +
        otherAssembleMs;
    final v = nativeBuildMs - assembleTotal;
    return v < 0 ? 0 : v;
  }

  /// `flutterBuildMs - dartMs`, clamped at 0. The "everything except Dart
  /// compilation" bucket inside Flutter's build. For caching analysis,
  /// prefer [nativeCompileMs] which isolates the native-toolchain portion.
  int get nonDartMs {
    final v = flutterBuildMs - dartMs;
    return v < 0 ? 0 : v;
  }

  /// Total command wall-clock (Flutter build + Shorebird overhead), when the
  /// overhead is known; otherwise just [flutterBuildMs].
  int get totalMs => flutterBuildMs + (shorebirdOverheadMs ?? 0);

  /// JSON representation suitable for writing alongside the raw trace.
  /// Field names are stable and safe to upload — no paths or identifiers.
  Map<String, Object?> toJson() => {
    'version': 3,
    'platform': platform,
    'totalMs': totalMs,
    'flutterBuildMs': flutterBuildMs,
    'shorebirdOverheadMs': shorebirdOverheadMs,
    'dartMs': dartMs,
    'nonDartMs': nonDartMs,
    'nativeCompileMs': nativeCompileMs,
    'kernelSnapshotMs': kernelSnapshotMs,
    'genSnapshotMs': genSnapshotMs,
    'dartBuildMs': dartBuildMs,
    'assetsMs': assetsMs,
    'codegenMs': codegenMs,
    'otherAssembleMs': otherAssembleMs,
    'flutterToolMs': flutterToolMs,
    'nativeBuildMs': nativeBuildMs,
    'assembleTargetCount': assembleTargetCount,
    'skippedAssembleTargetCount': skippedAssembleTargetCount,
  };
}

enum _AssembleCategory {
  kernelSnapshot,
  genSnapshot,
  dartBuild,
  assets,
  codegen,
  other,
}

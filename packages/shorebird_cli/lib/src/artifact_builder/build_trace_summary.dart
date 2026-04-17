import 'dart:convert';
import 'dart:io';

import 'package:shorebird_cli/src/artifact_builder/build_environment.dart';

/// A privacy-safe summary of a Chrome Trace Event Format build trace.
///
/// Contains only aggregate millisecond timings and small integer counters —
/// no target names, file paths, user identifiers, or other free-form fields
/// that could identify the project. This is the data we're willing to upload
/// to Shorebird servers to understand slow builds in the wild.
///
/// Schema version 5. Bumped when the on-wire JSON shape changes.
class BuildTraceSummary {
  /// Creates a [BuildTraceSummary] directly from pre-computed fields.
  /// Most callers should use [BuildTraceSummary.fromEvents] or
  /// [BuildTraceSummary.tryFromFile].
  BuildTraceSummary({
    required this.platform,
    required this.totalMs,
    required this.flutterBuildMs,
    required this.shorebirdOverheadMs,
    required this.network,
    required this.dart,
    required this.flutterAssemble,
    required this.native,
    required this.flutterToolMs,
    this.android,
    this.ios,
    this.environment,
  });

  /// Build a summary from the raw list of trace events written by Flutter
  /// (and merged with Shorebird-side events).
  ///
  /// [platform] is `android` or `ios`. Platform-specific stats ([android] /
  /// [ios]) are only populated for the matching platform.
  /// [shorebirdOverhead] captures Shorebird's own wall-clock time around
  /// `flutter build` — null when the caller can't compute it.
  factory BuildTraceSummary.fromEvents(
    List<Map<String, Object?>> events, {
    required String platform,
    Duration? shorebirdOverhead,
    BuildEnvironment? environment,
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
    var skippedAssembleCount = 0;
    var networkUs = 0;
    var networkCount = 0;
    // Gradle per-task stats (android).
    var kotlinCompileUs = 0;
    var javaCompileUs = 0;
    var dexUs = 0;
    var resourcesUs = 0;
    var transformUs = 0;
    var r8MinifyUs = 0;
    var lintUs = 0;
    var flutterGradlePluginUs = 0;
    var bundleUs = 0;
    var packagingUs = 0;
    var aidlUs = 0;
    var nativeLinkUs = 0;
    var gradleScaffoldUs = 0;
    var gradleTaskFromCacheCount = 0;
    var gradleTaskUpToDateCount = 0;
    var gradleTaskExecutedCount = 0;
    final gradleTaskDurationsUs = <int>[];
    // Pod install phase stats (ios).
    var podInstallUs = 0;
    var podAnalyzeUs = 0;
    var podDownloadUs = 0;
    var podGenerateUs = 0;
    var podIntegrateUs = 0;
    // Xcode subsection stats (ios). Populated from xcresulttool-derived
    // per-subsection events. Subsection titles are high-variance ("Build
    // target <name>", "Archive target <name>", etc.) so the summary keeps
    // aggregates and a histogram rather than name-keyed totals.
    var xcodeSubsectionCount = 0;
    var xcodeSubsectionSumUs = 0;
    final xcodeSubsectionDurationsUs = <int>[];

    for (final e in events) {
      final dur = (e['dur'] as num?)?.toInt() ?? 0;
      final tid = (e['tid'] as num?)?.toInt() ?? 0;
      final name = (e['name'] as String?) ?? '';
      final cat = (e['cat'] as String?) ?? '';
      final args = (e['args'] as Map?) ?? const {};
      final skipped = args['skipped'] == true;

      // tid 1 = flutter tool, tid 2 = native build system (gradle/xcode),
      // tid 3 = flutter assemble targets, tid 4 = per-task spans (gradle
      // on Android, xcode phases on iOS), tid 5 = Shorebird + HTTP.
      if (tid == 1) {
        if (name.startsWith('flutter build ')) {
          flutterBuildUs = dur;
        } else if (cat == 'subprocess') {
          if (name == 'pod install') {
            podInstallUs += dur;
          } else if (name == 'pod install: analyzing') {
            podAnalyzeUs += dur;
          } else if (name == 'pod install: downloading') {
            podDownloadUs += dur;
          } else if (name == 'pod install: generating') {
            podGenerateUs += dur;
          } else if (name == 'pod install: integrating') {
            podIntegrateUs += dur;
          }
        } else {
          flutterToolUs += dur;
        }
      } else if (tid == 2) {
        nativeBuildUs += dur;
      } else if (tid == 3) {
        assembleCount++;
        if (skipped) skippedAssembleCount++;
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
      } else if (tid == 4) {
        if (cat == 'gradle_task') {
          gradleTaskDurationsUs.add(dur);
          // Per-task cache outcome from the init script. Mutually
          // exclusive in practice: a task either ran, was up-to-date
          // (incremental skip), or was restored from the build cache.
          if (args['fromCache'] == true) {
            gradleTaskFromCacheCount++;
          } else if (args['upToDate'] == true) {
            gradleTaskUpToDateCount++;
          } else {
            gradleTaskExecutedCount++;
          }
          switch (args['kind']) {
            case 'kotlin_compile':
              kotlinCompileUs += dur;
            case 'java_compile':
              javaCompileUs += dur;
            case 'dex':
              dexUs += dur;
            case 'resources':
              resourcesUs += dur;
            case 'transform':
              transformUs += dur;
            case 'r8_minify':
              r8MinifyUs += dur;
            case 'lint':
              lintUs += dur;
            case 'flutter_gradle_plugin':
              flutterGradlePluginUs += dur;
            case 'bundle':
              bundleUs += dur;
            case 'packaging':
              packagingUs += dur;
            case 'aidl':
              aidlUs += dur;
            case 'native_link':
              nativeLinkUs += dur;
            case 'gradle_scaffold':
              gradleScaffoldUs += dur;
          }
        } else if (cat == 'xcode_subsection') {
          xcodeSubsectionCount++;
          xcodeSubsectionSumUs += dur;
          xcodeSubsectionDurationsUs.add(dur);
        }
      } else if (cat == 'network') {
        networkUs += dur;
        networkCount++;
      }
    }

    final (p50, p90, max) = _percentiles(gradleTaskDurationsUs);
    final gradleSumUs = gradleTaskDurationsUs.fold<int>(0, (a, b) => a + b);
    final (xcodeP50, xcodeP90, xcodeMax) = _percentiles(
      xcodeSubsectionDurationsUs,
    );

    // Dart-compile total (the "dart vs non-dart" signal lives inside
    // [DartStats]).
    final dart = DartStats(
      totalMs: (kernelSnapshotUs + genSnapshotUs) ~/ 1000,
      kernelSnapshotMs: kernelSnapshotUs ~/ 1000,
      genSnapshotMs: genSnapshotUs ~/ 1000,
      buildMs: dartBuildUs ~/ 1000,
    );
    final flutterAssemble = FlutterAssembleStats(
      assetsMs: assetsUs ~/ 1000,
      codegenMs: codegenUs ~/ 1000,
      otherMs: otherAssembleUs ~/ 1000,
      targetCount: assembleCount,
      skippedCount: skippedAssembleCount,
    );
    // "Native compile only" = native outer minus everything flutter
    // assemble reported running inside it. Clamped at 0 because the sum
    // can exceed nativeBuildUs in edge cases.
    final assembleTotalUs =
        kernelSnapshotUs +
        genSnapshotUs +
        dartBuildUs +
        assetsUs +
        codegenUs +
        otherAssembleUs;
    final nativeCompileUs = (nativeBuildUs - assembleTotalUs).clamp(
      0,
      1 << 62,
    );
    final native = NativeBuildStats(
      buildMs: nativeBuildUs ~/ 1000,
      compileMs: nativeCompileUs ~/ 1000,
    );

    AndroidStats? android;
    IosStats? ios;
    if (platform == 'android') {
      android = AndroidStats(
        gradle: GradleStats(
          taskCount: gradleTaskDurationsUs.length,
          taskSumMs: gradleSumUs ~/ 1000,
          taskP50Ms: p50 ~/ 1000,
          taskP90Ms: p90 ~/ 1000,
          taskMaxMs: max ~/ 1000,
          taskFromCacheCount: gradleTaskFromCacheCount,
          taskUpToDateCount: gradleTaskUpToDateCount,
          taskExecutedCount: gradleTaskExecutedCount,
          kotlinCompileMs: kotlinCompileUs ~/ 1000,
          javaCompileMs: javaCompileUs ~/ 1000,
          dexMs: dexUs ~/ 1000,
          resourcesMs: resourcesUs ~/ 1000,
          transformMs: transformUs ~/ 1000,
          r8MinifyMs: r8MinifyUs ~/ 1000,
          lintMs: lintUs ~/ 1000,
          flutterGradlePluginMs: flutterGradlePluginUs ~/ 1000,
          bundleMs: bundleUs ~/ 1000,
          packagingMs: packagingUs ~/ 1000,
          aidlMs: aidlUs ~/ 1000,
          nativeLinkMs: nativeLinkUs ~/ 1000,
          gradleScaffoldMs: gradleScaffoldUs ~/ 1000,
        ),
      );
    } else if (platform == 'ios') {
      ios = IosStats(
        podInstall: PodInstallStats(
          ms: podInstallUs ~/ 1000,
          analyzeMs: podAnalyzeUs ~/ 1000,
          downloadMs: podDownloadUs ~/ 1000,
          generateMs: podGenerateUs ~/ 1000,
          integrateMs: podIntegrateUs ~/ 1000,
        ),
        xcode: XcodeStats(
          subsectionCount: xcodeSubsectionCount,
          subsectionSumMs: xcodeSubsectionSumUs ~/ 1000,
          subsectionP50Ms: xcodeP50 ~/ 1000,
          subsectionP90Ms: xcodeP90 ~/ 1000,
          subsectionMaxMs: xcodeMax ~/ 1000,
        ),
      );
    }

    final flutterBuildMs = flutterBuildUs ~/ 1000;
    final shorebirdOverheadMs = shorebirdOverhead?.inMilliseconds;
    return BuildTraceSummary(
      platform: platform,
      totalMs: flutterBuildMs + (shorebirdOverheadMs ?? 0),
      flutterBuildMs: flutterBuildMs,
      shorebirdOverheadMs: shorebirdOverheadMs,
      network: NetworkStats(
        ms: networkUs ~/ 1000,
        callCount: networkCount,
      ),
      dart: dart,
      flutterAssemble: flutterAssemble,
      native: native,
      flutterToolMs: flutterToolUs ~/ 1000,
      android: android,
      ios: ios,
      environment: environment,
    );
  }

  /// Parse [traceFile] and return a summary, or null if the file is missing
  /// or can't be parsed as a Chrome Trace Event Format JSON array.
  static BuildTraceSummary? tryFromFile(
    File traceFile, {
    required String platform,
    Duration? shorebirdOverhead,
    BuildEnvironment? environment,
  }) {
    final events = tryReadEvents(traceFile);
    if (events == null) return null;
    return BuildTraceSummary.fromEvents(
      events,
      platform: platform,
      shorebirdOverhead: shorebirdOverhead,
      environment: environment,
    );
  }

  /// Parse [traceFile] once as a Chrome Trace Event Format JSON array and
  /// return the raw event list. Returns null if the file is missing or
  /// malformed. Callers that need to build more than one summary from the
  /// same trace (e.g. once to measure flutter wall clock, again with
  /// Shorebird overhead computed from it) should parse once and pass the
  /// list to [fromEvents] — parsing a multi-megabyte trace twice is wasted
  /// work on plugin-heavy apps.
  static List<Map<String, Object?>>? tryReadEvents(File traceFile) {
    if (!traceFile.existsSync()) return null;
    try {
      final decoded = jsonDecode(traceFile.readAsStringSync());
      final list = decoded is List
          ? decoded
          : (decoded is Map ? decoded['traceEvents'] as List? : null);
      if (list == null) return null;
      return list.cast<Map<String, Object?>>();
    } on FormatException {
      return null;
    }
  }

  static _AssembleCategory _categorize(String name) {
    final n = name.toLowerCase();
    if (n.contains('kernel_snapshot') || n == 'kernel') {
      return _AssembleCategory.kernelSnapshot;
    }
    if (n.startsWith('android_aot') ||
        n.contains('aot_assembly') ||
        n.contains('aot_elf') ||
        n == 'ios_aot' ||
        n.contains('aot_bundle')) {
      return _AssembleCategory.genSnapshot;
    }
    if (n == 'dart_build') {
      return _AssembleCategory.dartBuild;
    }
    if (n.startsWith('gen_')) {
      return _AssembleCategory.codegen;
    }
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

  static (int, int, int) _percentiles(List<int> values) {
    if (values.isEmpty) return (0, 0, 0);
    final sorted = [...values]..sort();
    int at(double q) {
      final idx = (sorted.length * q).floor().clamp(0, sorted.length - 1);
      return sorted[idx];
    }

    return (at(0.5), at(0.9), sorted.last);
  }

  /// `android` or `ios`.
  final String platform;

  /// Total command wall-clock (Flutter build + Shorebird overhead).
  final int totalMs;

  /// Flutter's own reported wall-clock duration (the `flutter build *`
  /// umbrella event in the trace).
  final int flutterBuildMs;

  /// Wall-clock time the Shorebird CLI spent around Flutter. Null when
  /// the caller couldn't compute it.
  final int? shorebirdOverheadMs;

  /// Network I/O time and request counts, summed across Shorebird-side
  /// HTTP (auth, artifact upload) and Flutter-side HTTP (artifact
  /// downloads when the cache is cold).
  final NetworkStats network;

  /// Dart-compilation breakdown (kernel snapshot + gen_snapshot) plus the
  /// `dart_build` user script target, which is tracked separately.
  final DartStats dart;

  /// Flutter assemble sub-invocation durations by bucket.
  final FlutterAssembleStats flutterAssemble;

  /// Native (Gradle/Xcode) outer span and derived "native-only compile"
  /// approximation.
  final NativeBuildStats native;

  /// Time in the flutter tool itself (pre/post setup), excluding the
  /// umbrella span.
  final int flutterToolMs;

  /// Android-specific stats. Only non-null when `platform == 'android'`.
  final AndroidStats? android;

  /// iOS-specific stats. Only non-null when `platform == 'ios'`.
  final IosStats? ios;

  /// Build-environment snapshot — caching configuration, CI provider,
  /// etc. Lets us tell apart "slow because nothing's configured" from
  /// "slow despite caching being on" in field data.
  final BuildEnvironment? environment;

  /// "Dart vs non-Dart" quick access: equivalent to `dart.totalMs`.
  int get dartMs => dart.totalMs;

  /// `flutterBuildMs - dartMs`, clamped at 0. The "everything except
  /// Dart compilation" bucket.
  int get nonDartMs {
    final v = flutterBuildMs - dartMs;
    return v < 0 ? 0 : v;
  }

  /// JSON representation suitable for writing alongside the raw trace.
  /// Field names are stable and safe to upload — no paths or identifiers.
  /// Platform-specific sections are omitted (not nulled) on the other
  /// platform.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': 6,
    'platform': platform,
    'totalMs': totalMs,
    'flutterBuildMs': flutterBuildMs,
    'shorebirdOverheadMs': shorebirdOverheadMs,
    'dartMs': dartMs,
    'nonDartMs': nonDartMs,
    'network': network.toJson(),
    'dart': dart.toJson(),
    'flutterAssemble': flutterAssemble.toJson(),
    'native': native.toJson(),
    'flutterTool': <String, Object?>{'ms': flutterToolMs},
    'android': ?android?.toJson(),
    'ios': ?ios?.toJson(),
    'environment': ?environment?.toJson(),
  };
}

/// Network I/O totals. Combined across Shorebird-side (auth, artifact
/// upload, etc.) and Flutter-side (artifact downloads) HTTP.
class NetworkStats {
  /// Creates a [NetworkStats].
  NetworkStats({required this.ms, required this.callCount});

  /// Total time across all HTTP requests, in milliseconds.
  final int ms;

  /// Number of HTTP requests.
  final int callCount;

  /// JSON form.
  Map<String, Object?> toJson() => {'ms': ms, 'callCount': callCount};
}

/// Dart compilation: source → kernel, kernel → native AOT, plus `dart_build`
/// user-script execution.
class DartStats {
  /// Creates a [DartStats].
  DartStats({
    required this.totalMs,
    required this.kernelSnapshotMs,
    required this.genSnapshotMs,
    required this.buildMs,
  });

  /// `kernelSnapshotMs + genSnapshotMs` — the pure Dart-compile total.
  final int totalMs;

  /// Dart frontend (source → kernel `.dill`).
  final int kernelSnapshotMs;

  /// gen_snapshot AOT (kernel → native code), summed across architectures.
  final int genSnapshotMs;

  /// `dart_build` target — runs user-authored `build.dart` scripts.
  /// Reported separately because it's Dart work, but not *compilation*.
  final int buildMs;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'totalMs': totalMs,
    'kernelSnapshotMs': kernelSnapshotMs,
    'genSnapshotMs': genSnapshotMs,
    'buildMs': buildMs,
  };
}

/// Flutter-assemble internal targets excluding the dart-compile ones.
class FlutterAssembleStats {
  /// Creates a [FlutterAssembleStats].
  FlutterAssembleStats({
    required this.assetsMs,
    required this.codegenMs,
    required this.otherMs,
    required this.targetCount,
    required this.skippedCount,
  });

  /// Asset bundling and framework unpacking.
  final int assetsMs;

  /// `gen_*` code generation.
  final int codegenMs;

  /// Residual assemble targets not matching any other bucket.
  final int otherMs;

  /// Total flutter assemble targets that appeared in the trace.
  final int targetCount;

  /// Targets that reported `skipped: true` (cache hits).
  final int skippedCount;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'assetsMs': assetsMs,
    'codegenMs': codegenMs,
    'otherMs': otherMs,
    'targetCount': targetCount,
    'skippedCount': skippedCount,
  };
}

/// Native toolchain outer span + derived "pure native compile" estimate.
class NativeBuildStats {
  /// Creates a [NativeBuildStats].
  NativeBuildStats({required this.buildMs, required this.compileMs});

  /// Gradle (Android) or Xcode (iOS) outer span duration.
  final int buildMs;

  /// Upper-bound for time a Flutter-aware native build cache could save:
  /// `buildMs` minus every flutter assemble target summed together.
  final int compileMs;

  /// JSON form.
  Map<String, Object?> toJson() => {'buildMs': buildMs, 'compileMs': compileMs};
}

/// Platform-specific Android stats.
class AndroidStats {
  /// Creates an [AndroidStats].
  AndroidStats({required this.gradle});

  /// Per-task Gradle breakdown.
  final GradleStats gradle;

  /// JSON form.
  Map<String, Object?> toJson() => {'gradle': gradle.toJson()};
}

/// Gradle task histogram + per-kind totals. Populated from the
/// `shorebird_trace_init.gradle` TaskExecutionListener.
class GradleStats {
  /// Creates a [GradleStats].
  GradleStats({
    required this.taskCount,
    required this.taskSumMs,
    required this.taskP50Ms,
    required this.taskP90Ms,
    required this.taskMaxMs,
    required this.taskFromCacheCount,
    required this.taskUpToDateCount,
    required this.taskExecutedCount,
    required this.kotlinCompileMs,
    required this.javaCompileMs,
    required this.dexMs,
    required this.resourcesMs,
    required this.transformMs,
    required this.r8MinifyMs,
    required this.lintMs,
    required this.flutterGradlePluginMs,
    required this.bundleMs,
    required this.packagingMs,
    required this.aidlMs,
    required this.nativeLinkMs,
    required this.gradleScaffoldMs,
  });

  /// Total number of Gradle tasks observed.
  final int taskCount;

  /// Sum of all task durations. Typically much larger than gradle wall
  /// clock because Gradle runs tasks in parallel.
  final int taskSumMs;

  /// p50 (median) of individual task durations in milliseconds.
  final int taskP50Ms;

  /// p90 of individual task durations in milliseconds.
  final int taskP90Ms;

  /// Max of individual task durations in milliseconds.
  final int taskMaxMs;

  /// Tasks restored from Gradle's build cache (FROM-CACHE skip message).
  /// Non-zero indicates `org.gradle.caching=true` is doing real work.
  final int taskFromCacheCount;

  /// Tasks that Gradle saw as up-to-date and skipped without running.
  /// Incremental-build hits.
  final int taskUpToDateCount;

  /// Tasks that actually executed (cache miss + not up-to-date).
  final int taskExecutedCount;

  /// Kotlin compilation time across plugins.
  final int kotlinCompileMs;

  /// Java compilation time across plugins.
  final int javaCompileMs;

  /// Dex (D8/R8 output) time.
  final int dexMs;

  /// Resource merging / processing time.
  final int resourcesMs;

  /// AAR / jetifier / desugar transform time.
  final int transformMs;

  /// R8 / minify / shrinking. Often the single slowest task on release
  /// builds.
  final int r8MinifyMs;

  /// Android lint (`lintVitalAnalyzeRelease` etc.). AGP runs these on
  /// every release build by default and they can dominate.
  final int lintMs;

  /// The Flutter Gradle plugin's own orchestration tasks (e.g.
  /// `compileFlutterBuildRelease`).
  final int flutterGradlePluginMs;

  /// Bundle-related Gradle tasks (AAB packaging etc.).
  final int bundleMs;

  /// APK packaging tasks.
  final int packagingMs;

  /// AIDL interface compilation.
  final int aidlMs;

  /// Merging / linking native libraries.
  final int nativeLinkMs;

  /// Per-plugin scaffolding — AAR metadata, proguard rule export,
  /// validate/check tasks, misc. `prepare*` / `copy*` / `generate*` not
  /// claimed by a more specific bucket.
  final int gradleScaffoldMs;

  /// JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
    'taskCount': taskCount,
    'taskSumMs': taskSumMs,
    'taskP50Ms': taskP50Ms,
    'taskP90Ms': taskP90Ms,
    'taskMaxMs': taskMaxMs,
    'taskFromCacheCount': taskFromCacheCount,
    'taskUpToDateCount': taskUpToDateCount,
    'taskExecutedCount': taskExecutedCount,
    'kotlinCompileMs': kotlinCompileMs,
    'javaCompileMs': javaCompileMs,
    'dexMs': dexMs,
    'resourcesMs': resourcesMs,
    'transformMs': transformMs,
    'r8MinifyMs': r8MinifyMs,
    'lintMs': lintMs,
    'flutterGradlePluginMs': flutterGradlePluginMs,
    'bundleMs': bundleMs,
    'packagingMs': packagingMs,
    'aidlMs': aidlMs,
    'nativeLinkMs': nativeLinkMs,
    'gradleScaffoldMs': gradleScaffoldMs,
  };
}

/// Platform-specific iOS stats.
class IosStats {
  /// Creates an [IosStats].
  IosStats({required this.podInstall, required this.xcode});

  /// CocoaPods `pod install` timing, split into phases.
  final PodInstallStats podInstall;

  /// Xcode per-phase breakdown from `-showBuildTimingSummary`.
  final XcodeStats xcode;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'podInstall': podInstall.toJson(),
    'xcode': xcode.toJson(),
  };
}

/// CocoaPods `pod install` timing, split into phases parsed from the
/// `--verbose` output: analyze, download, generate project, integrate.
class PodInstallStats {
  /// Creates a [PodInstallStats].
  PodInstallStats({
    required this.ms,
    required this.analyzeMs,
    required this.downloadMs,
    required this.generateMs,
    required this.integrateMs,
  });

  /// Total `pod install` wall-clock time.
  final int ms;

  /// Dependency analysis phase.
  final int analyzeMs;

  /// Downloading pods / dependencies phase.
  final int downloadMs;

  /// Generating the Pods Xcode project phase.
  final int generateMs;

  /// Integrating pods into the client Xcode project phase.
  final int integrateMs;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'ms': ms,
    'analyzeMs': analyzeMs,
    'downloadMs': downloadMs,
    'generateMs': generateMs,
    'integrateMs': integrateMs,
  };
}

/// Xcode per-phase totals parsed from the `-showBuildTimingSummary` block.
/// Xcode per-subsection aggregates from the structured build log emitted
/// by `xcrun xcresulttool get log --type build`. Each top-level
/// subsection is a target or build action ("Build target X", "Archive
/// target Y", "Compile Swift module Z", ...); subsection titles are
/// high-variance and potentially identifying, so we keep a histogram
/// rather than per-title totals.
class XcodeStats {
  /// Creates an [XcodeStats].
  XcodeStats({
    required this.subsectionCount,
    required this.subsectionSumMs,
    required this.subsectionP50Ms,
    required this.subsectionP90Ms,
    required this.subsectionMaxMs,
  });

  /// Number of top-level subsections Xcode reported (roughly, per-target
  /// build actions).
  final int subsectionCount;

  /// Sum of all subsection durations. Often much larger than the
  /// `xcode archive` wall clock because Xcode runs targets in parallel.
  final int subsectionSumMs;

  /// Median of individual subsection durations in milliseconds.
  final int subsectionP50Ms;

  /// 90th-percentile subsection duration.
  final int subsectionP90Ms;

  /// Longest subsection duration.
  final int subsectionMaxMs;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'subsectionCount': subsectionCount,
    'subsectionSumMs': subsectionSumMs,
    'subsectionP50Ms': subsectionP50Ms,
    'subsectionP90Ms': subsectionP90Ms,
    'subsectionMaxMs': subsectionMaxMs,
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

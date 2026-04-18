// This file is the consumer end of a string-level contract shared with
// the trace producers (flutter_tools, aot_tools, the Gradle init
// script, the CocoaPods wrapper). Event category names, gradle task
// `kind` values, and span-name prefixes live in
// `shorebird_build_trace`'s `TraceSchema`; if you add a new bucket
// here, add the matching producer-side constant there.

import 'dart:convert';
import 'dart:io';

import 'package:shorebird_build_trace/shorebird_build_trace.dart';
import 'package:shorebird_cli/src/artifact_builder/build_environment.dart';

/// Summary of a Chrome Trace Event Format build trace.
///
/// Aggregate millisecond timings and small integer counters, suitable
/// for uploading to Shorebird's servers as part of release telemetry.
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
    final acc = _Accumulator();
    for (final e in events) {
      // Skip metadata (`ph: "M"`) and flow (`ph: "s"`/`"f"`) events —
      // they don't carry a duration to bucket, they just label the
      // producer / draw causality arrows in Perfetto.
      if (e['ph'] != 'X') continue;
      _processEvent(acc, e);
    }
    return _buildSummary(
      acc,
      platform: platform,
      shorebirdOverhead: shorebirdOverhead,
      environment: environment,
    );
  }

  /// Dispatches a single `ph:"X"` event into the right accumulator
  /// bucket based on its `cat` and (for ambiguous cats) its `name`.
  /// Unknown categories fall through via [TraceCategory.unknown]; the
  /// switch stays exhaustive.
  static void _processEvent(_Accumulator acc, Map<String, Object?> e) {
    final dur = (e['dur'] as num?)?.toInt() ?? 0;
    final name = (e['name'] as String?) ?? '';
    final args =
        (e['args'] as Map<Object?, Object?>?) ?? const <Object?, Object?>{};
    switch (TraceCategory.parse(e['cat'] as String?)) {
      case TraceCategory.flutter:
        _processFlutterEvent(acc, name: name, dur: dur);
      case TraceCategory.subprocess:
        _processSubprocessEvent(acc, name: name, dur: dur);
      case TraceCategory.gradle:
      case TraceCategory.xcode:
        acc.nativeBuildUs += dur;
      case TraceCategory.assemble:
        acc.assembleCount++;
        if (args['skipped'] == true) acc.skippedAssembleCount++;
        acc.assembleCategoryUs.add(_categorize(name), dur);
      case TraceCategory.gradleTask:
        _processGradleTaskEvent(acc, dur: dur, args: args);
      case TraceCategory.xcodeSubsection:
        acc.xcodeSubsectionCount++;
        acc.xcodeSubsectionSumUs += dur;
        acc.xcodeSubsectionDurationsUs.add(dur);
      case TraceCategory.network:
        acc.networkUs += dur;
        acc.networkCount++;
      case TraceCategory.unknown:
        // Future producer version emitted a category we don't know.
        // Dropped on purpose — bucketing it anywhere else would lie.
        break;
    }
  }

  static void _processFlutterEvent(
    _Accumulator acc, {
    required String name,
    required int dur,
  }) {
    // Flutter emits exactly one `flutter build <target>` umbrella span
    // per invocation and zero-or-more flutter-tool sub-spans
    // (pre-build setup, post-build processing). `+=` works for both
    // since "exactly one" is a special case of "sum".
    if (name.startsWith(TraceNames.flutterBuildSpanPrefix)) {
      acc.flutterBuildUs += dur;
    } else {
      acc.flutterToolUs += dur;
    }
  }

  static void _processSubprocessEvent(
    _Accumulator acc, {
    required String name,
    required int dur,
  }) {
    if (name == TraceNames.podInstallSpanName) {
      acc.podInstallUs += dur;
      return;
    }
    const prefix = '${TraceNames.podInstallNamePrefix}: ';
    if (name.startsWith(prefix)) {
      acc.podPhaseUs.add(
        PodInstallPhase.parse(name.substring(prefix.length)),
        dur,
      );
    }
  }

  static void _processGradleTaskEvent(
    _Accumulator acc, {
    required int dur,
    required Map<Object?, Object?> args,
  }) {
    acc.gradleTaskDurationsUs.add(dur);
    // Per-task cache outcome from the init script. Mutually exclusive
    // in practice: a task either ran, was up-to-date (incremental
    // skip), or was restored from the build cache.
    if (args['fromCache'] == true) {
      acc.gradleTaskFromCacheCount++;
    } else if (args['upToDate'] == true) {
      acc.gradleTaskUpToDateCount++;
    } else {
      acc.gradleTaskExecutedCount++;
    }
    acc.gradleKindUs.add(
      GradleTaskKind.parse(args['kind'] as String?),
      dur,
    );
  }

  static BuildTraceSummary _buildSummary(
    _Accumulator acc, {
    required String platform,
    Duration? shorebirdOverhead,
    BuildEnvironment? environment,
  }) {
    final flutterBuildMs = _usToMs(acc.flutterBuildUs);
    final shorebirdOverheadMs = shorebirdOverhead?.inMilliseconds;
    return BuildTraceSummary(
      platform: platform,
      totalMs: flutterBuildMs + (shorebirdOverheadMs ?? 0),
      flutterBuildMs: flutterBuildMs,
      shorebirdOverheadMs: shorebirdOverheadMs,
      network: NetworkStats(
        ms: _usToMs(acc.networkUs),
        callCount: acc.networkCount,
      ),
      dart: _dartStats(acc),
      flutterAssemble: _flutterAssembleStats(acc),
      native: _nativeStats(acc),
      flutterToolMs: _usToMs(acc.flutterToolUs),
      android: platform == 'android' ? _androidStats(acc) : null,
      ios: platform == 'ios' ? _iosStats(acc) : null,
      environment: environment,
    );
  }

  static DartStats _dartStats(_Accumulator acc) {
    final kernel = acc.assembleCategoryUs.of(_AssembleCategory.kernelSnapshot);
    final gen = acc.assembleCategoryUs.of(_AssembleCategory.genSnapshot);
    return DartStats(
      totalMs: _usToMs(kernel + gen),
      kernelSnapshotMs: _usToMs(kernel),
      genSnapshotMs: _usToMs(gen),
      buildMs: _usToMs(acc.assembleCategoryUs.of(_AssembleCategory.dartBuild)),
    );
  }

  static FlutterAssembleStats _flutterAssembleStats(_Accumulator acc) {
    return FlutterAssembleStats(
      assetsMs: _usToMs(acc.assembleCategoryUs.of(_AssembleCategory.assets)),
      codegenMs: _usToMs(acc.assembleCategoryUs.of(_AssembleCategory.codegen)),
      otherMs: _usToMs(acc.assembleCategoryUs.of(_AssembleCategory.other)),
      targetCount: acc.assembleCount,
      skippedCount: acc.skippedAssembleCount,
    );
  }

  static NativeBuildStats _nativeStats(_Accumulator acc) {
    // "Native compile only" = native outer minus everything flutter
    // assemble reported running inside it. Clamped at 0 because the
    // sum can exceed nativeBuildUs in edge cases.
    final assembleTotalUs = acc.assembleCategoryUs.values.fold<int>(
      0,
      (a, b) => a + b,
    );
    final nativeCompileUs = (acc.nativeBuildUs - assembleTotalUs).clamp(
      0,
      1 << 62,
    );
    return NativeBuildStats(
      buildMs: _usToMs(acc.nativeBuildUs),
      compileMs: _usToMs(nativeCompileUs),
    );
  }

  static AndroidStats _androidStats(_Accumulator acc) {
    final (p50, p90, max) = _percentiles(acc.gradleTaskDurationsUs);
    final gradleSumUs = acc.gradleTaskDurationsUs.fold<int>(
      0,
      (a, b) => a + b,
    );
    int kindMs(GradleTaskKind k) => _usToMs(acc.gradleKindUs.of(k));
    return AndroidStats(
      gradle: GradleStats(
        taskCount: acc.gradleTaskDurationsUs.length,
        taskSumMs: _usToMs(gradleSumUs),
        taskP50Ms: _usToMs(p50),
        taskP90Ms: _usToMs(p90),
        taskMaxMs: _usToMs(max),
        taskFromCacheCount: acc.gradleTaskFromCacheCount,
        taskUpToDateCount: acc.gradleTaskUpToDateCount,
        taskExecutedCount: acc.gradleTaskExecutedCount,
        kotlinCompileMs: kindMs(GradleTaskKind.kotlinCompile),
        javaCompileMs: kindMs(GradleTaskKind.javaCompile),
        dexMs: kindMs(GradleTaskKind.dex),
        resourcesMs: kindMs(GradleTaskKind.resources),
        transformMs: kindMs(GradleTaskKind.transform),
        r8MinifyMs: kindMs(GradleTaskKind.r8Minify),
        lintMs: kindMs(GradleTaskKind.lint),
        flutterGradlePluginMs: kindMs(GradleTaskKind.flutterGradlePlugin),
        bundleMs: kindMs(GradleTaskKind.bundle),
        packagingMs: kindMs(GradleTaskKind.packaging),
        aidlMs: kindMs(GradleTaskKind.aidl),
        nativeLinkMs: kindMs(GradleTaskKind.nativeLink),
        gradleScaffoldMs: kindMs(GradleTaskKind.gradleScaffold),
      ),
    );
  }

  static IosStats _iosStats(_Accumulator acc) {
    final (xcodeP50, xcodeP90, xcodeMax) = _percentiles(
      acc.xcodeSubsectionDurationsUs,
    );
    int phaseMs(PodInstallPhase p) => _usToMs(acc.podPhaseUs.of(p));
    return IosStats(
      podInstall: PodInstallStats(
        ms: _usToMs(acc.podInstallUs),
        analyzeMs: phaseMs(PodInstallPhase.analyzing),
        downloadMs: phaseMs(PodInstallPhase.downloading),
        generateMs: phaseMs(PodInstallPhase.generating),
        integrateMs: phaseMs(PodInstallPhase.integrating),
      ),
      xcode: XcodeStats(
        subsectionCount: acc.xcodeSubsectionCount,
        subsectionSumMs: _usToMs(acc.xcodeSubsectionSumUs),
        subsectionP50Ms: _usToMs(xcodeP50),
        subsectionP90Ms: _usToMs(xcodeP90),
        subsectionMaxMs: _usToMs(xcodeMax),
      ),
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

/// Truncating microseconds → milliseconds. Chrome Trace Event Format
/// timestamps are in microseconds; this summary reports in milliseconds
/// to keep the JSON shape compact for telemetry.
int _usToMs(int us) => us ~/ 1000;

/// Mutable scratch struct that [BuildTraceSummary.fromEvents] fills
/// while iterating the event list, then [_buildSummary] consumes. Its
/// only job is to carry typed counters without needing ~30 positional
/// arguments between the per-event handlers.
class _Accumulator {
  int flutterBuildUs = 0;
  int flutterToolUs = 0;
  int nativeBuildUs = 0;
  int assembleCount = 0;
  int skippedAssembleCount = 0;
  int networkUs = 0;
  int networkCount = 0;
  int podInstallUs = 0;
  int xcodeSubsectionCount = 0;
  int xcodeSubsectionSumUs = 0;

  /// Per-bucket totals, keyed by the enum/category that classified the
  /// event. Read via [Map.operator[]] with a null-coalesce to 0 —
  /// unpopulated buckets (e.g. gradle kinds on an iOS build) never
  /// allocate an entry.
  final assembleCategoryUs = <_AssembleCategory, int>{};
  final gradleKindUs = <GradleTaskKind, int>{};
  final podPhaseUs = <PodInstallPhase, int>{};

  int gradleTaskFromCacheCount = 0;
  int gradleTaskUpToDateCount = 0;
  int gradleTaskExecutedCount = 0;
  final gradleTaskDurationsUs = <int>[];
  // Xcode subsection titles are high-variance ("Build target <name>",
  // "Archive target <name>", etc.) so the summary keeps aggregates and
  // a histogram rather than name-keyed totals.
  final xcodeSubsectionDurationsUs = <int>[];
}

extension on Map<dynamic, int> {
  /// Adds [value] to the counter keyed by [key], initializing from 0.
  void add<K>(K key, int value) {
    this[key] = (this[key] ?? 0) + value;
  }

  /// Reads the counter keyed by [key], returning 0 if unset. Sugar for
  /// `map[key] ?? 0` that keeps [_buildSummary]'s field list flat.
  int of<K>(K key) => this[key] ?? 0;
}

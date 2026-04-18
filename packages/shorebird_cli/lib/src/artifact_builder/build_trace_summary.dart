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
import 'package:shorebird_cli/src/artifact_builder/duration_distribution.dart';

/// Summary of a Chrome Trace Event Format build trace.
///
/// Aggregate [Duration] timings and small integer counters, suitable
/// for uploading to Shorebird's servers as part of release telemetry.
class BuildTraceSummary {
  /// Creates a [BuildTraceSummary] directly from pre-computed fields.
  /// Most callers should use [BuildTraceSummary.fromEvents] or
  /// [BuildTraceSummary.tryFromFile].
  BuildTraceSummary({
    required this.platform,
    required this.total,
    required this.flutterBuild,
    required this.shorebirdOverhead,
    required this.network,
    required this.dart,
    required this.flutterAssemble,
    required this.native,
    required this.flutterTool,
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
    final dur = Duration(microseconds: (e['dur'] as num?)?.toInt() ?? 0);
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
        acc.nativeBuild += dur;
      case TraceCategory.assemble:
        acc.assembleCount++;
        if (args['skipped'] == true) acc.skippedAssembleCount++;
        acc.assembleCategory.add(_categorize(name), dur);
      case TraceCategory.gradleTask:
        _processGradleTaskEvent(acc, dur: dur, args: args);
      case TraceCategory.xcodeSubsection:
        acc.xcodeSubsectionDurations.add(dur);
      case TraceCategory.network:
        acc.network += dur;
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
    required Duration dur,
  }) {
    // Flutter emits exactly one `flutter build <target>` umbrella span
    // per invocation and zero-or-more flutter-tool sub-spans
    // (pre-build setup, post-build processing). `+=` works for both
    // since "exactly one" is a special case of "sum".
    if (name.startsWith(TraceNames.flutterBuildSpanPrefix)) {
      acc.flutterBuild += dur;
    } else {
      acc.flutterTool += dur;
    }
  }

  static void _processSubprocessEvent(
    _Accumulator acc, {
    required String name,
    required Duration dur,
  }) {
    const prefix = '${TraceNames.podInstallNamePrefix}: ';
    if (name == TraceNames.podInstallSpanName) {
      acc.podInstall = acc.podInstall + dur;
    } else if (name.startsWith(prefix)) {
      acc.podPhase.add(
        PodInstallPhase.parse(name.substring(prefix.length)),
        dur,
      );
    }
  }

  static void _processGradleTaskEvent(
    _Accumulator acc, {
    required Duration dur,
    required Map<Object?, Object?> args,
  }) {
    acc.gradleTaskDurations.add(dur);
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
    acc.gradleKind.add(
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
    final flutterBuild = acc.flutterBuild;
    return BuildTraceSummary(
      platform: platform,
      total: flutterBuild + (shorebirdOverhead ?? Duration.zero),
      flutterBuild: flutterBuild,
      shorebirdOverhead: shorebirdOverhead,
      network: NetworkStats(
        duration: acc.network,
        callCount: acc.networkCount,
      ),
      dart: _dartStats(acc),
      flutterAssemble: _flutterAssembleStats(acc),
      native: _nativeStats(acc),
      flutterTool: acc.flutterTool,
      android: platform == 'android' ? _androidStats(acc) : null,
      ios: platform == 'ios' ? _iosStats(acc) : null,
      environment: environment,
    );
  }

  static DartStats _dartStats(_Accumulator acc) {
    final kernel = acc.assembleCategory.of(_AssembleCategory.kernelSnapshot);
    final gen = acc.assembleCategory.of(_AssembleCategory.genSnapshot);
    return DartStats(
      total: kernel + gen,
      kernelSnapshot: kernel,
      genSnapshot: gen,
      build: acc.assembleCategory.of(_AssembleCategory.dartBuild),
    );
  }

  static FlutterAssembleStats _flutterAssembleStats(_Accumulator acc) {
    return FlutterAssembleStats(
      assets: acc.assembleCategory.of(_AssembleCategory.assets),
      codegen: acc.assembleCategory.of(_AssembleCategory.codegen),
      other: acc.assembleCategory.of(_AssembleCategory.other),
      targetCount: acc.assembleCount,
      skippedCount: acc.skippedAssembleCount,
    );
  }

  static NativeBuildStats _nativeStats(_Accumulator acc) {
    // "Native compile only" = native outer minus everything flutter
    // assemble reported running inside it. Clamped at 0 because the
    // sum can exceed nativeBuild in edge cases.
    final assembleTotal = acc.assembleCategory.values.fold(
      Duration.zero,
      (a, b) => a + b,
    );
    final rawNativeCompile = acc.nativeBuild - assembleTotal;
    final nativeCompile = rawNativeCompile < Duration.zero
        ? Duration.zero
        : rawNativeCompile;
    return NativeBuildStats(
      build: acc.nativeBuild,
      compile: nativeCompile,
    );
  }

  static AndroidStats _androidStats(_Accumulator acc) {
    Duration kindDur(GradleTaskKind k) => acc.gradleKind.of(k);
    return AndroidStats(
      gradle: GradleStats(
        taskDistribution: DurationDistribution.fromDurations(
          acc.gradleTaskDurations,
        ),
        taskFromCacheCount: acc.gradleTaskFromCacheCount,
        taskUpToDateCount: acc.gradleTaskUpToDateCount,
        taskExecutedCount: acc.gradleTaskExecutedCount,
        kotlinCompile: kindDur(GradleTaskKind.kotlinCompile),
        javaCompile: kindDur(GradleTaskKind.javaCompile),
        dex: kindDur(GradleTaskKind.dex),
        resources: kindDur(GradleTaskKind.resources),
        transform: kindDur(GradleTaskKind.transform),
        r8Minify: kindDur(GradleTaskKind.r8Minify),
        lint: kindDur(GradleTaskKind.lint),
        flutterGradlePlugin: kindDur(GradleTaskKind.flutterGradlePlugin),
        bundle: kindDur(GradleTaskKind.bundle),
        packaging: kindDur(GradleTaskKind.packaging),
        aidl: kindDur(GradleTaskKind.aidl),
        nativeLink: kindDur(GradleTaskKind.nativeLink),
        gradleScaffold: kindDur(GradleTaskKind.gradleScaffold),
      ),
    );
  }

  static IosStats _iosStats(_Accumulator acc) {
    Duration phaseDur(PodInstallPhase p) => acc.podPhase.of(p);
    return IosStats(
      podInstall: PodInstallStats(
        duration: acc.podInstall,
        analyze: phaseDur(PodInstallPhase.analyzing),
        download: phaseDur(PodInstallPhase.downloading),
        generate: phaseDur(PodInstallPhase.generating),
        integrate: phaseDur(PodInstallPhase.integrating),
      ),
      xcode: XcodeStats(
        subsectionDistribution: DurationDistribution.fromDurations(
          acc.xcodeSubsectionDurations,
        ),
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

  /// `android` or `ios`.
  final String platform;

  /// Total command wall-clock (Flutter build + Shorebird overhead).
  final Duration total;

  /// Flutter's own reported wall-clock duration (the `flutter build *`
  /// umbrella event in the trace).
  final Duration flutterBuild;

  /// Wall-clock time the Shorebird CLI spent around Flutter. Null when
  /// the caller couldn't compute it.
  final Duration? shorebirdOverhead;

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
  final Duration flutterTool;

  /// Android-specific stats. Only non-null when `platform == 'android'`.
  final AndroidStats? android;

  /// iOS-specific stats. Only non-null when `platform == 'ios'`.
  final IosStats? ios;

  /// Build-environment snapshot — caching configuration, CI provider,
  /// etc. Lets us tell apart "slow because nothing's configured" from
  /// "slow despite caching being on" in field data.
  final BuildEnvironment? environment;

  /// Shorebird CLI's wall-clock time around Flutter with network I/O
  /// subtracted — i.e. what Shorebird spent doing local work (file I/O,
  /// hashing, archive assembly, aot_tools link/gen_snapshot bookkeeping
  /// outside their own spans). Null when [shorebirdOverhead] is null.
  ///
  /// Clamped to zero if the network tally exceeds overhead (can happen
  /// when flutter's own downloads are counted in network but executed
  /// inside the flutterBuild span, which is already subtracted from
  /// overhead).
  Duration? get shorebirdLocal {
    final overhead = shorebirdOverhead;
    if (overhead == null) return null;
    final local = overhead - network.duration;
    return local.isNegative ? Duration.zero : local;
  }

  /// JSON representation suitable for writing alongside the raw trace.
  /// Field names are stable and safe to upload — no paths or identifiers.
  /// Platform-specific sections are omitted (not nulled) on the other
  /// platform.
  ///
  /// `dart`'s total lives inside the `dart` sub-object (`dart.totalMs`);
  /// no redundant top-level `dartMs`. `nonDart` is a consumer-side
  /// subtraction (`flutterBuildMs - dart.totalMs`) — kept out of the
  /// on-wire shape so there's exactly one way to read each value.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': 8,
    'platform': platform,
    'totalMs': total.inMilliseconds,
    'flutterBuildMs': flutterBuild.inMilliseconds,
    'shorebirdOverheadMs': shorebirdOverhead?.inMilliseconds,
    'shorebirdLocalMs': shorebirdLocal?.inMilliseconds,
    'network': network.toJson(),
    'dart': dart.toJson(),
    'flutterAssemble': flutterAssemble.toJson(),
    'native': native.toJson(),
    'flutterTool': <String, Object?>{'ms': flutterTool.inMilliseconds},
    'android': ?android?.toJson(),
    'ios': ?ios?.toJson(),
    'environment': ?environment?.toJson(),
  };
}

/// Network I/O totals. Combined across Shorebird-side (auth, artifact
/// upload, etc.) and Flutter-side (artifact downloads) HTTP.
class NetworkStats {
  /// Creates a [NetworkStats].
  NetworkStats({required this.duration, required this.callCount});

  /// Total time across all HTTP requests.
  final Duration duration;

  /// Number of HTTP requests.
  final int callCount;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'ms': duration.inMilliseconds,
    'callCount': callCount,
  };
}

/// Dart compilation: source → kernel, kernel → native AOT, plus `dart_build`
/// user-script execution.
class DartStats {
  /// Creates a [DartStats].
  DartStats({
    required this.total,
    required this.kernelSnapshot,
    required this.genSnapshot,
    required this.build,
  });

  /// `kernelSnapshot + genSnapshot` — the pure Dart-compile total.
  final Duration total;

  /// Dart frontend (source → kernel `.dill`).
  final Duration kernelSnapshot;

  /// gen_snapshot AOT (kernel → native code), summed across architectures.
  final Duration genSnapshot;

  /// `dart_build` target — runs user-authored `build.dart` scripts.
  /// Reported separately because it's Dart work, but not *compilation*.
  final Duration build;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'totalMs': total.inMilliseconds,
    'kernelSnapshotMs': kernelSnapshot.inMilliseconds,
    'genSnapshotMs': genSnapshot.inMilliseconds,
    'buildMs': build.inMilliseconds,
  };
}

/// Flutter-assemble internal targets excluding the dart-compile ones.
class FlutterAssembleStats {
  /// Creates a [FlutterAssembleStats].
  FlutterAssembleStats({
    required this.assets,
    required this.codegen,
    required this.other,
    required this.targetCount,
    required this.skippedCount,
  });

  /// Asset bundling and framework unpacking.
  final Duration assets;

  /// `gen_*` code generation.
  final Duration codegen;

  /// Residual assemble targets not matching any other bucket.
  final Duration other;

  /// Total flutter assemble targets that appeared in the trace.
  final int targetCount;

  /// Targets that reported `skipped: true` (cache hits).
  final int skippedCount;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'assetsMs': assets.inMilliseconds,
    'codegenMs': codegen.inMilliseconds,
    'otherMs': other.inMilliseconds,
    'targetCount': targetCount,
    'skippedCount': skippedCount,
  };
}

/// Native toolchain outer span + derived "pure native compile" estimate.
class NativeBuildStats {
  /// Creates a [NativeBuildStats].
  NativeBuildStats({required this.build, required this.compile});

  /// Gradle (Android) or Xcode (iOS) outer span duration.
  final Duration build;

  /// Upper-bound for time a Flutter-aware native build cache could save:
  /// `build` minus every flutter assemble target summed together.
  final Duration compile;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'buildMs': build.inMilliseconds,
    'compileMs': compile.inMilliseconds,
  };
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
    required this.taskDistribution,
    required this.taskFromCacheCount,
    required this.taskUpToDateCount,
    required this.taskExecutedCount,
    required this.kotlinCompile,
    required this.javaCompile,
    required this.dex,
    required this.resources,
    required this.transform,
    required this.r8Minify,
    required this.lint,
    required this.flutterGradlePlugin,
    required this.bundle,
    required this.packaging,
    required this.aidl,
    required this.nativeLink,
    required this.gradleScaffold,
  });

  /// Distribution of per-task durations (count, sum, p50, p90, max).
  /// Sum is typically much larger than gradle wall clock because Gradle
  /// runs tasks in parallel.
  final DurationDistribution taskDistribution;

  /// Tasks restored from Gradle's build cache (FROM-CACHE skip message).
  /// Non-zero indicates `org.gradle.caching=true` is doing real work.
  final int taskFromCacheCount;

  /// Tasks that Gradle saw as up-to-date and skipped without running.
  /// Incremental-build hits.
  final int taskUpToDateCount;

  /// Tasks that actually executed (cache miss + not up-to-date).
  final int taskExecutedCount;

  /// Kotlin compilation time across plugins.
  final Duration kotlinCompile;

  /// Java compilation time across plugins.
  final Duration javaCompile;

  /// Dex (D8/R8 output) time.
  final Duration dex;

  /// Resource merging / processing time.
  final Duration resources;

  /// AAR / jetifier / desugar transform time.
  final Duration transform;

  /// R8 / minify / shrinking. Often the single slowest task on release
  /// builds.
  final Duration r8Minify;

  /// Android lint (`lintVitalAnalyzeRelease` etc.). AGP runs these on
  /// every release build by default and they can dominate.
  final Duration lint;

  /// The Flutter Gradle plugin's own orchestration tasks (e.g.
  /// `compileFlutterBuildRelease`).
  final Duration flutterGradlePlugin;

  /// Bundle-related Gradle tasks (AAB packaging etc.).
  final Duration bundle;

  /// APK packaging tasks.
  final Duration packaging;

  /// AIDL interface compilation.
  final Duration aidl;

  /// Merging / linking native libraries.
  final Duration nativeLink;

  /// Per-plugin scaffolding — AAR metadata, proguard rule export,
  /// validate/check tasks, misc. `prepare*` / `copy*` / `generate*` not
  /// claimed by a more specific bucket.
  final Duration gradleScaffold;

  /// JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
    'taskDistribution': taskDistribution.toJson(),
    'taskFromCacheCount': taskFromCacheCount,
    'taskUpToDateCount': taskUpToDateCount,
    'taskExecutedCount': taskExecutedCount,
    'kotlinCompileMs': kotlinCompile.inMilliseconds,
    'javaCompileMs': javaCompile.inMilliseconds,
    'dexMs': dex.inMilliseconds,
    'resourcesMs': resources.inMilliseconds,
    'transformMs': transform.inMilliseconds,
    'r8MinifyMs': r8Minify.inMilliseconds,
    'lintMs': lint.inMilliseconds,
    'flutterGradlePluginMs': flutterGradlePlugin.inMilliseconds,
    'bundleMs': bundle.inMilliseconds,
    'packagingMs': packaging.inMilliseconds,
    'aidlMs': aidl.inMilliseconds,
    'nativeLinkMs': nativeLink.inMilliseconds,
    'gradleScaffoldMs': gradleScaffold.inMilliseconds,
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
    required this.duration,
    required this.analyze,
    required this.download,
    required this.generate,
    required this.integrate,
  });

  /// Total `pod install` wall-clock time.
  final Duration duration;

  /// Dependency analysis phase.
  final Duration analyze;

  /// Downloading pods / dependencies phase.
  final Duration download;

  /// Generating the Pods Xcode project phase.
  final Duration generate;

  /// Integrating pods into the client Xcode project phase.
  final Duration integrate;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'ms': duration.inMilliseconds,
    'analyzeMs': analyze.inMilliseconds,
    'downloadMs': download.inMilliseconds,
    'generateMs': generate.inMilliseconds,
    'integrateMs': integrate.inMilliseconds,
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
  XcodeStats({required this.subsectionDistribution});

  /// Distribution of per-subsection durations (count, sum, p50, p90,
  /// max). Sum is often much larger than the `xcode archive` wall clock
  /// because Xcode runs targets in parallel.
  final DurationDistribution subsectionDistribution;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'subsectionDistribution': subsectionDistribution.toJson(),
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

/// Mutable scratch struct that [BuildTraceSummary.fromEvents] fills
/// while iterating the event list, then [_buildSummary] consumes. Its
/// only job is to carry typed counters without needing ~30 positional
/// arguments between the per-event handlers.
class _Accumulator {
  Duration flutterBuild = Duration.zero;
  Duration flutterTool = Duration.zero;
  Duration nativeBuild = Duration.zero;
  int assembleCount = 0;
  int skippedAssembleCount = 0;
  Duration network = Duration.zero;
  int networkCount = 0;
  Duration podInstall = Duration.zero;

  /// Per-bucket totals, keyed by the enum/category that classified the
  /// event. Read via [Map.operator[]] with a null-coalesce to
  /// [Duration.zero] — unpopulated buckets (e.g. gradle kinds on an iOS
  /// build) never allocate an entry.
  final assembleCategory = <_AssembleCategory, Duration>{};
  final gradleKind = <GradleTaskKind, Duration>{};
  final podPhase = <PodInstallPhase, Duration>{};

  int gradleTaskFromCacheCount = 0;
  int gradleTaskUpToDateCount = 0;
  int gradleTaskExecutedCount = 0;
  final gradleTaskDurations = <Duration>[];
  // Xcode subsection titles are high-variance ("Build target <name>",
  // "Archive target <name>", etc.) so the summary keeps aggregates and
  // a histogram rather than name-keyed totals.
  final xcodeSubsectionDurations = <Duration>[];
}

extension on Map<dynamic, Duration> {
  /// Adds [value] to the counter keyed by [key], initializing from
  /// [Duration.zero].
  void add<K>(K key, Duration value) {
    this[key] = (this[key] ?? Duration.zero) + value;
  }

  /// Reads the counter keyed by [key], returning [Duration.zero] if
  /// unset. Sugar for `map[key] ?? Duration.zero` that keeps
  /// [_buildSummary]'s field list flat.
  Duration of<K>(K key) => this[key] ?? Duration.zero;
}

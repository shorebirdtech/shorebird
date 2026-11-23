// This file is the consumer end of a string-level contract shared with
// the trace producers (flutter_tools, aot_tools, the Gradle init
// script, the CocoaPods wrapper). Event category names, gradle task
// `kind` values, and span-name prefixes live in
// `shorebird_build_trace`'s `trace_schema.dart`; if you add a new bucket
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
  /// Most callers should use [BuildTraceSummary.fromEvents].
  BuildTraceSummary({
    required this.platform,
    required this.total,
    required this.flutterBuild,
    required this.shorebirdOverhead,
    required this.network,
    required this.setup,
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
  /// [platform] is the release platform name (`android`, `ios`, `macos`,
  /// `linux`, `windows`). Platform-specific stats are only populated
  /// where the build system produces them: [android] for `android`,
  /// [ios] for every xcodebuild-driven platform (`ios`, `macos`).
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
    return BuildTraceSummary._fromAccumulator(
      acc,
      platform: platform,
      shorebirdOverhead: shorebirdOverhead,
      environment: environment,
    );
  }

  /// Assembles the summary from the counters [BuildTraceSummary.fromEvents]
  /// accumulated.
  factory BuildTraceSummary._fromAccumulator(
    _Accumulator acc, {
    required String platform,
    Duration? shorebirdOverhead,
    BuildEnvironment? environment,
  }) {
    final flutterBuild = acc.flutterBuild;
    final setupSpans = _Spans.union(_knownSetupPhases.map(acc.setupPhase.of));
    return BuildTraceSummary(
      platform: platform,
      total: flutterBuild + (shorebirdOverhead ?? Duration.zero),
      flutterBuild: flutterBuild,
      shorebirdOverhead: shorebirdOverhead,
      network: NetworkStats(
        duration: acc.network.wall,
        shorebird: acc.network.wallOutside(
          _Spans.union([setupSpans, acc.flutterBuildSpans]),
        ),
        callCount: acc.networkCount,
      ),
      setup: _setupStats(acc),
      dart: _dartStats(acc),
      flutterAssemble: _flutterAssembleStats(acc),
      native: _nativeStats(acc),
      flutterTool: acc.flutterTool,
      android: platform == 'android' ? _androidStats(acc) : null,
      ios: xcodePlatforms.contains(platform) ? _iosStats(acc) : null,
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
    final ts = (e['ts'] as num?)?.toInt();
    switch (TraceCategory.parse(e['cat'] as String?)) {
      case TraceCategory.flutter:
        _processFlutterEvent(acc, name: name, ts: ts, dur: dur);
      case TraceCategory.subprocess:
        _processSubprocessEvent(acc, name: name, dur: dur);
      case TraceCategory.gradle:
      case TraceCategory.xcode:
        acc.nativeBuild += dur;
        if (ts != null) acc.nativeSpans.add(_Interval(ts, dur));
      case TraceCategory.assemble:
        acc.assembleCount++;
        if (args['skipped'] == true) acc.skippedAssembleCount++;
        acc.assembleCategory.spans(_categorize(name)).add(ts, dur);
        acc.assembleSpans.add(ts, dur);
      case TraceCategory.gradleTask:
        _processGradleTaskEvent(acc, dur: dur, args: args);
      case TraceCategory.xcodeSubsection:
        acc.xcodeSubsectionDurations.add(dur);
      case TraceCategory.network:
        acc.network.add(ts, dur);
        acc.networkCount++;
      case TraceCategory.setup:
        _processSetupEvent(acc, name: name, ts: ts, dur: dur);
      case TraceCategory.download:
        acc.downloads.add(ts: ts, dur: dur, args: args);
      case TraceCategory.unknown:
        // Future producer version emitted a category we don't know.
        // Dropped on purpose — bucketing it anywhere else would lie.
        break;
    }
  }

  static void _processFlutterEvent(
    _Accumulator acc, {
    required String name,
    required int? ts,
    required Duration dur,
  }) {
    // Flutter emits exactly one `flutter build <target>` umbrella span
    // per invocation and zero-or-more flutter-tool sub-spans
    // (pre-build setup, post-build processing). `+=` works for both
    // since "exactly one" is a special case of "sum".
    if (name.startsWith(TraceNames.flutterBuildSpanPrefix)) {
      acc.flutterBuild += dur;
      acc.flutterBuildSpans.add(ts, dur);
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

  static void _processSetupEvent(
    _Accumulator acc, {
    required String name,
    required int? ts,
    required Duration dur,
  }) {
    const prefix = '${TraceNames.setupNamePrefix}: ';
    if (!name.startsWith(prefix)) return;
    acc.setupPhase
        .spans(SetupPhase.parse(name.substring(prefix.length)))
        .add(ts, dur);
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

  /// The setup phases [SetupStats.total] counts.
  static const _knownSetupPhases = [
    SetupPhase.flutterInstall,
    SetupPhase.flutterPrecache,
    SetupPhase.shorebirdCache,
  ];

  static SetupStats _setupStats(_Accumulator acc) {
    return SetupStats(
      total: _Spans.union(_knownSetupPhases.map(acc.setupPhase.of)).wall,
      flutterInstall: acc.setupPhase.of(SetupPhase.flutterInstall).wall,
      flutterPrecache: acc.setupPhase.of(SetupPhase.flutterPrecache).wall,
      shorebirdCache: acc.setupPhase.of(SetupPhase.shorebirdCache).wall,
      downloads: acc.downloads.stats(),
    );
  }

  static DartStats _dartStats(_Accumulator acc) {
    final kernel = acc.assembleCategory.of(_AssembleCategory.kernelSnapshot);
    final gen = acc.assembleCategory.of(_AssembleCategory.genSnapshot);
    return DartStats(
      total: _Spans.union([kernel, gen]).wall,
      kernelSnapshot: kernel.wall,
      genSnapshot: gen.wall,
      build: acc.assembleCategory.of(_AssembleCategory.dartBuild).wall,
    );
  }

  static FlutterAssembleStats _flutterAssembleStats(_Accumulator acc) {
    return FlutterAssembleStats(
      assets: acc.assembleCategory.of(_AssembleCategory.assets).wall,
      codegen: acc.assembleCategory.of(_AssembleCategory.codegen).wall,
      other: acc.assembleCategory.of(_AssembleCategory.other).wall,
      targetCount: acc.assembleCount,
      skippedCount: acc.skippedAssembleCount,
    );
  }

  static NativeBuildStats _nativeStats(_Accumulator acc) {
    // "Native compile only" = native outer minus the flutter assemble
    // time that actually ran inside it. On apk/appbundle/ios/macos,
    // assemble is a child of gradle/xcodebuild so that's all of it; on
    // ios-framework the App.framework targets are built in-process
    // beside the plugin xcodebuild runs, so only their overlap (typically
    // none) is subtracted. Overlap is measured from timestamps; an
    // assemble event with no `ts` is assumed nested, matching the
    // pre-timestamp behavior. Assemble targets run concurrently (one
    // gen_snapshot per Android arch), so their spans are merged first;
    // summing them would subtract the same wall time once per arch.
    // Clamped at 0 for edge cases.
    final nestedAssemble = acc.assembleSpans.merged.fold(
      Duration.zero,
      (sum, span) => sum + span.overlapWith(acc.nativeSpans),
    );
    final rawNativeCompile = acc.nativeBuild - nestedAssemble;
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

  /// Parse [traceFile] once as a Chrome Trace Event Format JSON array and
  /// return the raw event list. Returns null if the file is missing or
  /// malformed. Callers that need to build more than one summary from the
  /// same trace (e.g. once to measure flutter wall clock, again with
  /// Shorebird overhead computed from it) should parse once and pass the
  /// list to [BuildTraceSummary.fromEvents]. Parsing a multi-megabyte
  /// trace twice is wasted work on plugin-heavy apps.
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

  /// The release platform name this trace came from (`android`, `ios`,
  /// `macos`, `linux`, `windows`).
  final String platform;

  /// Total command wall-clock (Flutter build + Shorebird overhead).
  final Duration total;

  /// Flutter's own reported wall-clock duration (the `flutter build *`
  /// umbrella event in the trace).
  final Duration flutterBuild;

  /// Wall-clock time the Shorebird CLI spent around Flutter. Null when
  /// the caller couldn't compute it.
  final Duration? shorebirdOverhead;

  /// Network I/O time and request counts for HTTP shorebird_cli issues
  /// itself. Not a whole-command network total — see [NetworkStats].
  final NetworkStats network;

  /// Cold-start setup cost (Flutter install, precache, shorebird cache),
  /// broken out of [shorebirdOverhead]. See [SetupStats].
  final SetupStats setup;

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

  /// Xcode-driven build stats (pod install phases, xcodebuild target
  /// timings). Only non-null for a platform in [xcodePlatforms]; the JSON
  /// key stays `ios` for compatibility with existing consumers.
  final IosStats? ios;

  /// Platforms whose native build runs through xcodebuild and CocoaPods,
  /// so their traces carry the events [IosStats] is built from. Note
  /// `ios` covers `ios-framework` releases too — the CLI reports
  /// `ReleasePlatform.name`, which maps both to `ios`.
  static const xcodePlatforms = {'ios', 'macos'};

  /// Build-environment snapshot — caching configuration, CI provider,
  /// etc. Lets us tell apart "slow because nothing's configured" from
  /// "slow despite caching being on" in field data.
  final BuildEnvironment? environment;

  /// Shorebird CLI's wall-clock time around Flutter less its own network
  /// time ([NetworkStats.shorebird]). Null when [shorebirdOverhead] is
  /// null.
  ///
  /// It still holds [setup]: the fork clone, precache and shorebird-cache
  /// downloads. [NetworkStats.shorebird] leaves out every request inside
  /// setup, so subtracting [setup] as well (`shorebirdLocalMs -
  /// setup.totalMs`) gives Shorebird's local work (file I/O, hashing,
  /// archive assembly, linking) with nothing taken off twice. Before
  /// summary version 10 this subtracted all of [NetworkStats.duration],
  /// which counts the shorebird-cache downloads setup holds.
  ///
  /// Clamped to zero if the network time exceeds overhead.
  Duration? get shorebirdLocal {
    final overhead = shorebirdOverhead;
    if (overhead == null) return null;
    final local = overhead - network.shorebird;
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
    // 10: the trace holds no data from earlier commands; earlier versions
    // may sum every run since the last `flutter clean` (_shorebird#5890).
    // Dart, network, setup and assemble buckets are wall time (the union
    // of their spans), not sums; earlier versions sum concurrent
    // gen_snapshot runs once per arch. Gradle task kinds, pod phases,
    // xcode subsections and flutterTool are still sums: parallel gradle
    // tasks can add up to more than the native build.
    // network.shorebirdMs is new in 10, and shorebirdLocalMs subtracts it
    // rather than network.ms.
    // 11: setup.downloads, from the download spans a Flutter fork that
    // traces precache writes; zeros from one that doesn't.
    'version': 11,
    'platform': platform,
    'totalMs': total.inMilliseconds,
    'flutterBuildMs': flutterBuild.inMilliseconds,
    'shorebirdOverheadMs': shorebirdOverhead?.inMilliseconds,
    'shorebirdLocalMs': shorebirdLocal?.inMilliseconds,
    'network': network.toJson(),
    'setup': setup.toJson(),
    'dart': dart.toJson(),
    'flutterAssemble': flutterAssemble.toJson(),
    'native': native.toJson(),
    'flutterTool': <String, Object?>{'ms': flutterTool.inMilliseconds},
    'android': ?android?.toJson(),
    'ios': ?ios?.toJson(),
    'environment': ?environment?.toJson(),
  };
}

/// Network I/O totals for HTTP that shorebird_cli itself issues (auth,
/// Code Push API calls, cached-artifact downloads), plus any Flutter-side
/// requests made while flutter_tools has a `BuildTracer` installed.
///
/// Deliberately *not* a whole-command network total. Flutter downloads
/// its engine artifacts before it installs a tracer, and `git clone` and
/// `flutter precache` are subprocesses with their own sockets, so none of
/// that traffic is visible here. Those costs are attributed by
/// [SetupStats] instead; reading this field as "time the command spent
/// on the network" will understate a cold start by minutes.
class NetworkStats {
  /// Creates a [NetworkStats].
  NetworkStats({
    required this.duration,
    required this.shorebird,
    required this.callCount,
  });

  /// Wall time with any HTTP request in flight, measured from request
  /// start to the last byte of the response body (not to first byte).
  /// Concurrent requests count once.
  final Duration duration;

  /// The part of [duration] outside setup and the `flutter build` span:
  /// Shorebird's own requests (auth, Code Push API calls, uploads).
  /// [duration] also holds the shorebird-cache downloads [SetupStats]
  /// already counts, and any request Flutter traces inside its build
  /// (today's traces have none: every request is Shorebird's), so this
  /// is the network time to take out of Shorebird's overhead without
  /// counting any of it twice. Requests with no `ts` can't be placed and
  /// are counted here.
  final Duration shorebird;

  /// Number of HTTP requests.
  final int callCount;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'ms': duration.inMilliseconds,
    'shorebirdMs': shorebird.inMilliseconds,
    'callCount': callCount,
  };
}

/// Shorebird-side setup performed before `flutter build`: installing the
/// Flutter fork, precaching engine artifacts, and refreshing shorebird's
/// own cached artifacts.
///
/// Every field here is a subset of `shorebirdOverheadMs`. On a warm
/// machine all three are ~0. On a cold CI runner they are mostly
/// download time, and they are the only place that download time is
/// attributed — see [SetupPhase].
class SetupStats {
  /// Creates a [SetupStats].
  SetupStats({
    required this.total,
    required this.flutterInstall,
    required this.flutterPrecache,
    required this.shorebirdCache,
    required this.downloads,
  });

  /// Cloning the Flutter fork and checking out the pinned revision.
  final Duration flutterInstall;

  /// The `flutter precache` subprocess (engine artifact downloads).
  final Duration flutterPrecache;

  /// Refreshing shorebird's own cached artifacts: wall time across calls,
  /// overlapping calls counted once.
  final Duration shorebirdCache;

  /// Wall time in any setup phase. Phases can nest or overlap (cache
  /// refreshes run inside one another), so this can be less than their
  /// sum.
  final Duration total;

  /// The artifact downloads inside [flutterPrecache], one span each from
  /// a Flutter fork that traces them. All zero on a fork that doesn't,
  /// or when nothing needed precaching.
  final DownloadStats downloads;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'totalMs': total.inMilliseconds,
    'flutterInstallMs': flutterInstall.inMilliseconds,
    'flutterPrecacheMs': flutterPrecache.inMilliseconds,
    'shorebirdCacheMs': shorebirdCache.inMilliseconds,
    'downloads': downloads.toJson(),
  };
}

/// Flutter's artifact downloads during `flutter precache`: how many, how
/// big, how long, and which hosts and edges served them, so a slow cold
/// start can be told apart by where its bytes came from.
class DownloadStats {
  /// Creates a [DownloadStats].
  DownloadStats({
    required this.count,
    required this.cacheHitCount,
    required this.failedCount,
    required this.retryCount,
    required this.bytes,
    required this.duration,
    required this.redirect,
    required this.timeToFirstByte,
    required this.hosts,
    required this.edges,
  });

  /// Artifacts fetched (cache hits not counted).
  final int count;

  /// Artifacts already cached, so not fetched.
  final int cacheHitCount;

  /// Fetches that ended in an error or a status of 400 or more.
  final int failedCount;

  /// Attempts after the first, across every fetch.
  final int retryCount;

  /// Response bytes received.
  final int bytes;

  /// Wall time with any fetch in flight; concurrent fetches count once.
  final Duration duration;

  /// Time spent on redirects before the request that served the bytes,
  /// summed over fetches: unlike [duration] it is not wall time, so with
  /// concurrent fetches it can exceed [duration].
  final Duration redirect;

  /// Time to first byte of the request that served each fetch's bytes.
  final DurationDistribution timeToFirstByte;

  /// Fetches by the host that served their bytes.
  final Map<String, HostDownloadStats> hosts;

  /// Fetches by the edge that served them (`cloudflare:BOM`).
  final Map<String, int> edges;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'count': count,
    'cacheHitCount': cacheHitCount,
    'failedCount': failedCount,
    'retryCount': retryCount,
    'bytes': bytes,
    'ms': duration.inMilliseconds,
    'redirectMs': redirect.inMilliseconds,
    'ttfb': timeToFirstByte.toJson(),
    'hosts': {
      for (final MapEntry(:key, :value) in hosts.entries) key: value.toJson(),
    },
    'edges': edges,
  };
}

/// The fetches one host served.
class HostDownloadStats {
  /// Creates a [HostDownloadStats].
  HostDownloadStats({
    required this.count,
    required this.bytes,
    required this.duration,
  });

  /// Fetches the host served.
  final int count;

  /// Bytes it served.
  final int bytes;

  /// Wall time with any of its fetches in flight.
  final Duration duration;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'count': count,
    'bytes': bytes,
    'ms': duration.inMilliseconds,
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

  /// Wall time in kernelSnapshot or genSnapshot — the pure Dart-compile
  /// total.
  final Duration total;

  /// Dart frontend (source → kernel `.dill`).
  final Duration kernelSnapshot;

  /// gen_snapshot AOT (kernel → native code): wall time across
  /// architectures, which compile concurrently.
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
  /// `build` minus the wall time flutter assemble targets ran inside it.
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

/// Stats specific to xcodebuild-driven platforms (iOS and macOS).
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
/// while iterating the event list, then
/// [BuildTraceSummary._fromAccumulator] consumes. Its
/// only job is to carry typed counters without needing ~30 positional
/// arguments between the per-event handlers.
class _Accumulator {
  Duration flutterBuild = Duration.zero;

  /// The `flutter build` umbrella spans, so network time inside them can
  /// be told from Shorebird's own.
  final flutterBuildSpans = _Spans();
  Duration flutterTool = Duration.zero;
  Duration nativeBuild = Duration.zero;
  int assembleCount = 0;
  int skippedAssembleCount = 0;
  final network = _Spans();
  int networkCount = 0;
  Duration podInstall = Duration.zero;

  /// Per-bucket totals, keyed by the enum/category that classified the
  /// event. Read via [Map.operator[]] with a null-coalesce to
  /// [Duration.zero] — unpopulated buckets (e.g. gradle kinds on an iOS
  /// build) never allocate an entry.
  final gradleKind = <GradleTaskKind, Duration>{};
  final podPhase = <PodInstallPhase, Duration>{};

  /// Buckets whose events can run concurrently (one gen_snapshot per
  /// Android arch, parallel network requests, nested cache refreshes),
  /// kept as spans so each reports wall time rather than a sum.
  final assembleCategory = <_AssembleCategory, _Spans>{};
  final setupPhase = <SetupPhase, _Spans>{};

  int gradleTaskFromCacheCount = 0;
  int gradleTaskUpToDateCount = 0;
  int gradleTaskExecutedCount = 0;
  final gradleTaskDurations = <Duration>[];
  // Xcode subsection titles are high-variance ("Build target <name>",
  // "Archive target <name>", etc.) so the summary keeps aggregates and
  // a histogram rather than name-keyed totals.
  final xcodeSubsectionDurations = <Duration>[];

  /// Outer native-build spans (gradle / xcodebuild) and assemble spans,
  /// kept with timestamps so [BuildTraceSummary._nativeStats] can tell
  /// which assemble work ran inside the native build.
  final nativeSpans = <_Interval>[];
  final assembleSpans = _Spans();

  /// The artifact cache's downloads (`download` spans).
  final downloads = _Downloads();
}

/// Totals of the `download` spans flutter_tools writes during precache,
/// as [DownloadStats] reports them.
class _Downloads {
  /// Most distinct hosts or edges reported; the rest are summed under
  /// [_other]. A real precache sees two or three hosts and one edge.
  static const _maxKeys = 16;

  static const _other = 'other';

  /// A host or edge name as reported, or [_other] when it isn't a short
  /// plain name: these values come from response headers, and the
  /// summary leaves the machine.
  static final _plainName = RegExp(r'^[A-Za-z0-9._:-]{1,64}$');

  final spans = _Spans();
  int count = 0;
  int cacheHitCount = 0;
  int failedCount = 0;
  int retryCount = 0;
  int bytes = 0;
  Duration redirect = Duration.zero;
  final timesToFirstByte = <Duration>[];
  final hosts = <String, _HostDownloads>{};
  final edges = <String, int>{};

  void add({
    required int? ts,
    required Duration dur,
    required Map<Object?, Object?> args,
  }) {
    if (args[DownloadArgs.cacheHit] == true) {
      cacheHitCount++;
      return;
    }
    count++;
    spans.add(ts, dur);
    final size = _int(args[DownloadArgs.bytes]);
    bytes += size;
    retryCount += _int(args[DownloadArgs.retries]);
    redirect += Duration(microseconds: _int(args[DownloadArgs.redirectUs]));
    final ttfb = args[DownloadArgs.ttfbUs];
    if (ttfb is num) timesToFirstByte.add(Duration(microseconds: ttfb.toInt()));
    final status = args[DownloadArgs.status];
    final failed =
        args[DownloadArgs.error] != null || (status is num && status >= 400);
    if (failed) failedCount++;

    final host = _key(
      hosts,
      args[DownloadArgs.servedBy] ?? args[DownloadArgs.host],
    );
    (hosts[host] ??= _HostDownloads())
      ..count += 1
      ..bytes += size
      ..spans.add(ts, dur);
    final edge = args[DownloadArgs.edge];
    if (edge != null) {
      final key = _key(edges, edge);
      edges[key] = (edges[key] ?? 0) + 1;
    }
  }

  static int _int(Object? value) => value is num ? value.toInt() : 0;

  /// The key [value] is counted under in [map].
  static String _key(Map<String, Object?> map, Object? value) {
    if (value is! String || !_plainName.hasMatch(value)) return _other;
    if (map.containsKey(value) || map.length < _maxKeys) return value;
    return _other;
  }

  DownloadStats stats() => DownloadStats(
    count: count,
    cacheHitCount: cacheHitCount,
    failedCount: failedCount,
    retryCount: retryCount,
    bytes: bytes,
    duration: spans.wall,
    redirect: redirect,
    timeToFirstByte: DurationDistribution.fromDurations(timesToFirstByte),
    hosts: {
      for (final MapEntry(:key, :value) in hosts.entries)
        key: HostDownloadStats(
          count: value.count,
          bytes: value.bytes,
          duration: value.spans.wall,
        ),
    },
    edges: Map.unmodifiable(edges),
  );
}

class _HostDownloads {
  int count = 0;
  int bytes = 0;
  final spans = _Spans();
}

/// Spans of one bucket, reported as wall time: the length of their
/// union, so concurrent or repeated spans count once.
class _Spans {
  _Spans();

  /// The spans of every bucket in [buckets], together.
  _Spans.union(Iterable<_Spans> buckets) {
    for (final b in buckets) {
      _timed.addAll(b._timed);
      _withoutTs += b._withoutTs;
    }
  }

  final _timed = <_Interval>[];

  /// Total of spans with no `ts`, which can't be placed and so are
  /// summed, as before timestamps.
  Duration _withoutTs = Duration.zero;

  void add(int? ts, Duration dur) {
    if (ts == null) {
      _withoutTs += dur;
    } else {
      _timed.add(_Interval(ts, dur));
    }
  }

  /// The timed spans merged into disjoint intervals, in start order,
  /// then the spans without a `ts` as one total.
  List<_Interval> get merged {
    final sorted = [..._timed]..sort((a, b) => a.start!.compareTo(b.start!));
    final out = <_Interval>[];
    int? start;
    var end = 0;
    for (final i in sorted) {
      if (start != null && i.start! <= end) {
        if (i.end! > end) end = i.end!;
        continue;
      }
      if (start != null) {
        out.add(_Interval(start, Duration(microseconds: end - start)));
      }
      start = i.start;
      end = i.end!;
    }
    if (start != null) {
      out.add(_Interval(start, Duration(microseconds: end - start)));
    }
    if (_withoutTs > Duration.zero) out.add(_Interval(null, _withoutTs));
    return out;
  }

  /// Wall time: the length of the union of the timed spans plus the
  /// total of spans without a `ts`.
  Duration get wall => merged.fold(Duration.zero, (sum, i) => sum + i.dur);

  /// Wall time of these spans outside every span of [other]. Spans of
  /// either without a `ts` can't be placed: this side's count in full,
  /// [other]'s take nothing away.
  Duration wallOutside(_Spans other) {
    final others = other.merged.where((i) => i.start != null).toList();
    return merged.fold(
      Duration.zero,
      (sum, i) =>
          sum + (i.start == null ? i.dur : i.dur - i.overlapWith(others)),
    );
  }
}

/// A `[start, start + dur)` window in trace microseconds. [start] is
/// null when the event carried no `ts`.
class _Interval {
  const _Interval(this.start, this.dur);

  final int? start;
  final Duration dur;

  int? get end {
    final s = start;
    return s == null ? null : s + dur.inMicroseconds;
  }

  /// How much of this window falls inside any of [others]. A window with
  /// no timestamp is treated as fully inside — the producer predates
  /// timestamps, and every producer that old nested assemble in the
  /// native build. [others] are assumed non-overlapping (sequential
  /// gradle / xcodebuild invocations), so their overlaps simply sum.
  Duration overlapWith(List<_Interval> others) {
    final s = start;
    final e = end;
    if (s == null || e == null) return dur;
    var total = 0;
    for (final o in others) {
      final os = o.start;
      final oe = o.end;
      if (os == null || oe == null) continue;
      final lo = s > os ? s : os;
      final hi = e < oe ? e : oe;
      if (hi > lo) total += hi - lo;
    }
    return Duration(microseconds: total);
  }
}

extension<K> on Map<K, _Spans> {
  /// The spans for [key], created empty on first use.
  _Spans spans(K key) => putIfAbsent(key, _Spans.new);

  /// The spans for [key], empty if none were recorded.
  _Spans of(K key) => this[key] ?? _Spans();
}

extension on Map<dynamic, Duration> {
  /// Adds [value] to the counter keyed by [key], initializing from
  /// [Duration.zero].
  void add<K>(K key, Duration value) {
    this[key] = (this[key] ?? Duration.zero) + value;
  }

  /// Reads the counter keyed by [key], returning [Duration.zero] if
  /// unset. Sugar for `map[key] ?? Duration.zero` that keeps
  /// [BuildTraceSummary._fromAccumulator]'s field list flat.
  Duration of<K>(K key) => this[key] ?? Duration.zero;
}

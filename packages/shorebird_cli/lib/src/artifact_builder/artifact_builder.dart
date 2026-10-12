// cspell:words endtemplate aabs ipas appbundle bryanoltman codesign xcarchive
// cspell:words xcframework
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/build_environment.dart';
import 'package:shorebird_cli/src/artifact_builder/build_trace_session.dart';
import 'package:shorebird_cli/src/artifact_builder/build_trace_summary.dart';
import 'package:shorebird_cli/src/artifact_builder/legacy_flutter_jar.dart';
import 'package:shorebird_cli/src/artifact_builder/shorebird_tracer.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform.dart' as scoped_platform;
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// {@template artifact_build_exception}
/// Thrown when a build fails.
/// {@endtemplate}
class ArtifactBuildException implements Exception {
  /// {@macro artifact_build_exception}
  ArtifactBuildException(this.message, {this.fixRecommendation});

  /// Information about the build failure.
  final String message;

  /// An optional tip to help the user fix the build failure.
  final String? fixRecommendation;
}

/// Used to wrap code that invokes `flutter build` with Shorebird's fork of
/// Flutter.
typedef ShorebirdBuildCommand = Future<void> Function();

/// {@template apple_build_result}
/// Metadata about the result of a `flutter build` invocation for an apple
/// target.
/// {@endtemplate}
class AppleBuildResult {
  /// {@macro apple_build_result}
  AppleBuildResult({required this.kernelFile});

  /// The app.dill file produced.
  final File kernelFile;
}

/// A reference to a [ArtifactBuilder] instance.
final artifactBuilderRef = create(ArtifactBuilder.new);

/// The [ArtifactBuilder] instance available in the current zone.
ArtifactBuilder get artifactBuilder => read(artifactBuilderRef);

/// Builds the environment map for Flutter build subprocesses.
///
/// Merges the public key (if present) with any additional environment
/// variables (e.g. DD table configuration).
///
/// Environment variables are used (rather than command-line flags) for
/// backwards compatibility: older Flutter builds that don't recognize a
/// variable will silently ignore it, whereas an unknown flag would cause
/// a build failure.
Map<String, String>? buildEnvironment({
  String? base64PublicKey,
  int? ddMaxBytes,
}) {
  final env = <String, String>{};
  if (base64PublicKey != null) {
    env['SHOREBIRD_PUBLIC_KEY'] = base64PublicKey;
  }
  if (ddMaxBytes != null) {
    env['SHOREBIRD_DD_MAX_BYTES'] = ddMaxBytes.toString();
  }
  return env.isEmpty ? null : env;
}

/// @{template artifact_builder}
/// Builds aabs, ipas, and other artifacts produced by `flutter build`.
/// @{endtemplate}
class ArtifactBuilder {
  /// A general recommendation when building artifacts fails.
  static String runVanillaFlutterBuildRecommendation(String buildCommand) =>
      '''

${styleBold.wrap('💡 Fix Recommendations')}

• Check that running `flutter build` with the same command-line arguments
completes successfully by running the following command:

${lightCyan.wrap(buildCommand)}

If the above command fails, then this is likely not a Shorebird issue and
the underlying `flutter build` failure must be resolved for Shorebird to
build a release.

• If `flutter build` completes successfully, please ensure that you are
providing the desired flutter version to the release command via
the `--flutter-version` option. If you do not specify a `--flutter-version`
Shorebird will default to the latest stable version of Flutter.
We strongly encourage always specifying an explicit Flutter version:

${lightCyan.wrap('shorebird release <platform> --flutter-version=3.29.0')}

• If `flutter build` completes successfully and `shorebird release`
fails when using the same flutter version, please file an issue:
${link(uri: Uri.parse('https://github.com/shorebirdtech/shorebird/issues/new'))}
''';

  /// The fix recommendation for a failed Android build.
  ///
  /// Prepends a targeted hint to [runVanillaFlutterBuildRecommendation] when a
  /// plugin in the project still references the legacy `flutter.jar` artifact
  /// (see [LegacyFlutterJarReference]), which is the most common cause of an
  /// Android build that succeeds under `flutter build` but fails under
  /// `shorebird release`.
  String _androidBuildFixRecommendation(String buildCommand) {
    final vanilla = runVanillaFlutterBuildRecommendation(buildCommand);
    final projectRoot = shorebirdEnv.getShorebirdProjectRoot();
    if (projectRoot == null) return vanilla;
    final offenders = LegacyFlutterJarReference.findInProject(projectRoot);
    if (offenders.isEmpty) return vanilla;
    return '${LegacyFlutterJarReference.recommendation(offenders)}\n$vanilla';
  }

  /// Cache of `flutter build <command>` help output checks for
  /// `--shorebird-trace` support. Populated lazily by
  /// [_supportsTraceFlag].
  final _traceSupport = <String, bool>{};

  /// Returns whether `flutter build <command>` accepts `--shorebird-trace`.
  ///
  /// Probes the command's help output and caches the result per [command]
  /// so that subsequent calls for the same command are free.
  /// Returns `false` if the help check fails for any reason.
  ///
  /// The probe uses verbose help (`-h -v`): `--shorebird-trace` is registered
  /// with `hide: !verboseHelp` in Flutter, so it does not appear in plain
  /// `-h` output. Probing with `-h` alone therefore returned `false` even on
  /// Flutter versions that fully support the flag, silently disabling build
  /// tracing for everyone. `-h -v` lists hidden options so support is
  /// detected correctly.
  Future<bool> _supportsTraceFlag(String command) async {
    if (_traceSupport.containsKey(command)) return _traceSupport[command]!;

    try {
      final result = await process.run(
        'flutter',
        ['build', command, '-h', '-v'],
        runInShell: false,
      );
      final supported = result.stdout.toString().contains('--shorebird-trace');
      _traceSupport[command] = supported;
      return supported;
    } on Exception {
      _traceSupport[command] = false;
      return false;
    }
  }

  /// Returns the `--shorebird-trace` argument if the current
  /// [BuildTraceSession] has a trace file and the given [command]
  /// supports it, or an empty list otherwise.
  Future<List<String>> _traceArgs(String command) async {
    final traceFile = buildTraceSession.traceFile;
    if (traceFile == null) return const [];
    if (!await _supportsTraceFlag(command)) return const [];
    return ['--shorebird-trace=${traceFile.path}'];
  }

  /// Builds an aab using `flutter build appbundle`. Runs `flutter pub get` with
  /// the system installation of Flutter to reset
  /// `.dart_tool/package_config.json` after the build completes or fails.
  Future<File> buildAppBundle({
    String? flavor,
    String? target,
    Iterable<Arch>? targetPlatforms,
    List<String> args = const [],
    String? base64PublicKey,
    int? ddMaxBytes,
  }) async {
    final targetPlatformArgs = targetPlatforms?.targetPlatformArg;
    await _runShorebirdBuildCommand(
      () => _runFlutterBuild(
        command: 'appbundle',
        description: 'AAB',
        flags: [
          '--release',
          if (flavor != null) '--flavor=$flavor',
          if (target != null) '--target=$target',
          if (targetPlatformArgs != null)
            '--target-platform=$targetPlatformArgs',
        ],
        args: args,
        base64PublicKey: base64PublicKey,
        ddMaxBytes: ddMaxBytes,
        fixRecommendation: _androidBuildFixRecommendation,
      ),
    );

    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    return _findBuiltArtifact(
      'AAB',
      () => shorebirdAndroidArtifacts.findAab(
        project: projectRoot,
        flavor: flavor,
      ),
    );
  }

  /// Builds an APK using `flutter build apk`. Runs `flutter pub get` with the
  /// system installation of Flutter to reset `.dart_tool/package_config.json`
  /// after the build completes or fails.
  Future<File> buildApk({
    String? flavor,
    String? target,
    Iterable<Arch>? targetPlatforms,
    bool splitPerAbi = false,
    List<String> args = const [],
    String? base64PublicKey,
    int? ddMaxBytes,
  }) async {
    final targetPlatformArgs = targetPlatforms?.targetPlatformArg;
    await _runShorebirdBuildCommand(
      () => _runFlutterBuild(
        command: 'apk',
        description: 'APK',
        flags: [
          '--release',
          if (flavor != null) '--flavor=$flavor',
          if (target != null) '--target=$target',
          if (targetPlatformArgs != null)
            '--target-platform=$targetPlatformArgs',
          // TODO(bryanoltman): reintroduce coverage when we can support this.
          // See https://github.com/shorebirdtech/shorebird/issues/1141.
          // coverage:ignore-start
          if (splitPerAbi) '--split-per-abi',
          // coverage:ignore-end
        ],
        args: args,
        base64PublicKey: base64PublicKey,
        ddMaxBytes: ddMaxBytes,
        fixRecommendation: _androidBuildFixRecommendation,
      ),
    );

    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    return _findBuiltArtifact(
      'APK',
      () => shorebirdAndroidArtifacts.findApk(
        project: projectRoot,
        flavor: flavor,
      ),
    );
  }

  /// Builds an AAR using `flutter build aar`. Runs `flutter pub get` with the
  /// system installation of Flutter to reset `.dart_tool/package_config.json`
  /// after the build completes or fails.
  Future<void> buildAar({
    required String buildNumber,
    Iterable<Arch>? targetPlatforms,
    List<String> args = const [],
    String? base64PublicKey,
    int? ddMaxBytes,
  }) async {
    final targetPlatformArgs = targetPlatforms?.targetPlatformArg;
    await _runShorebirdBuildCommand(
      () => _runFlutterBuild(
        command: 'aar',
        description: 'AAR',
        flags: [
          '--no-debug',
          '--no-profile',
          '--build-number=$buildNumber',
          if (targetPlatformArgs != null)
            '--target-platform=$targetPlatformArgs',
        ],
        args: args,
        base64PublicKey: base64PublicKey,
        ddMaxBytes: ddMaxBytes,
        fixRecommendation: _androidBuildFixRecommendation,
      ),
    );
  }

  /// Builds a Linux desktop application by running `flutter build linux
  /// --release` with Shorebird's fork of Flutter.
  Future<void> buildLinuxApp({
    String? target,
    List<String> args = const [],
    String? base64PublicKey,
    int? ddMaxBytes,
  }) async {
    await _runShorebirdBuildCommand(
      () => _runFlutterBuild(
        command: 'linux',
        description: 'linux app',
        flags: ['--release', if (target != null) '--target=$target'],
        args: args,
        base64PublicKey: base64PublicKey,
        ddMaxBytes: ddMaxBytes,
      ),
    );
  }

  /// Builds a macOS app using `flutter build macos`. Runs `flutter pub get`
  /// with the system installation of Flutter to reset
  /// `.dart_tool/package_config.json` after the build completes or fails.
  Future<AppleBuildResult> buildMacos({
    bool codesign = true,
    String? flavor,
    String? target,
    List<String> args = const [],
    String? base64PublicKey,
    int? ddMaxBytes,
  }) {
    return _buildAppleKernel(
      command: 'macos',
      description: 'macOS app',
      flags: [
        '--release',
        if (flavor != null) '--flavor=$flavor',
        if (target != null) '--target=$target',
        if (!codesign) '--no-codesign',
      ],
      args: args,
      base64PublicKey: base64PublicKey,
      ddMaxBytes: ddMaxBytes,
    );
  }

  /// Calls `flutter build ipa`. If [codesign] is false, this will only build
  /// an .xcarchive and _not_ an .ipa.
  Future<AppleBuildResult> buildIpa({
    bool codesign = true,
    String? flavor,
    String? target,
    List<String> args = const [],
    String? base64PublicKey,
    int? ddMaxBytes,
  }) {
    return _buildAppleKernel(
      command: 'ipa',
      description: 'IPA',
      flags: [
        '--release',
        if (flavor != null) '--flavor=$flavor',
        if (target != null) '--target=$target',
        if (!codesign) '--no-codesign',
      ],
      args: args,
      base64PublicKey: base64PublicKey,
      ddMaxBytes: ddMaxBytes,
    );
  }

  /// Builds a release iOS framework (.xcframework) for the current project.
  Future<AppleBuildResult> buildIosFramework({
    List<String> args = const [],
    String? base64PublicKey,
    int? ddMaxBytes,
  }) {
    return _buildAppleKernel(
      command: 'ios-framework',
      description: 'iOS framework',
      flags: ['--no-debug', '--no-profile'],
      args: args,
      base64PublicKey: base64PublicKey,
      ddMaxBytes: ddMaxBytes,
    );
  }

  /// Runs `flutter build [command]` with [flags], the tracing args and [args],
  /// using Shorebird's fork of Flutter.
  ///
  /// Throws an [ArtifactBuildException] naming [description] if the build
  /// fails, with [fixRecommendation] applied to the full command. Returns the
  /// time just before `flutter` was spawned, so callers can find the files the
  /// build produced.
  Future<DateTime> _runFlutterBuild({
    required String command,
    required String description,
    required List<String> flags,
    required List<String> args,
    required String? base64PublicKey,
    required int? ddMaxBytes,
    String Function(String buildCommand) fixRecommendation =
        runVanillaFlutterBuildRecommendation,
  }) async {
    const executable = 'flutter';
    final arguments = [
      'build',
      command,
      ...flags,
      ...await _traceArgs(command),
      ...args,
    ];

    _deleteGeneratedShorebirdYamls(command);
    final buildStart = clock.now();
    final exitCode = await process.stream(
      executable,
      arguments,
      environment: buildEnvironment(
        base64PublicKey: base64PublicKey,
        ddMaxBytes: ddMaxBytes,
      ),
      // Never run in shell because we always have a fully resolved
      // executable path.
      runInShell: false,
      onStart: _emitFlutterSpawnFlow,
    );

    if (exitCode != ExitCode.success.code) {
      throw ArtifactBuildException(
        '''
Failed to build $description.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''',
        fixRecommendation: fixRecommendation(
          [executable, ...arguments].join(' '),
        ),
      );
    }

    return buildStart;
  }

  /// Deletes the generated (bundled) shorebird.yaml files that
  /// `flutter build [command]` regenerates, see [_generatedShorebirdYamls].
  ///
  /// There are two different files named shorebird.yaml. The project's
  /// shorebird.yaml is checked in at the project root and is never touched
  /// here. The generated (bundled) shorebird.yaml is the one Shorebird's
  /// Flutter writes into `flutter_assets` from the project's, adding keys
  /// such as `patch_public_key`.
  ///
  /// Flutter writes `patch_public_key` from the `SHOREBIRD_PUBLIC_KEY`
  /// environment variable, which neither Flutter's build system nor Gradle
  /// track as an input. When nothing else changed since the last build, both
  /// skip the step that writes the generated shorebird.yaml, and the app ships
  /// the previous build's copy with a stale or missing key. Flutter's build
  /// system and Gradle both rerun a step whose output is missing, so deleting
  /// the generated copy makes this build write a fresh one. Flutter's own
  /// cache still skips the targets whose outputs are intact, such as the AOT
  /// snapshot.
  ///
  /// This is best effort: a file that cannot be deleted is logged and the
  /// build goes ahead.
  void _deleteGeneratedShorebirdYamls(String command) {
    for (final file in _generatedShorebirdYamls(command)) {
      try {
        file.deleteSync();
      } on PathNotFoundException {
        // Nothing to delete.
      } on FileSystemException catch (error) {
        logger.detail(
          'Failed to delete generated shorebird.yaml at ${file.path}: $error',
        );
      }
    }
  }

  /// The generated (bundled) shorebird.yaml files that `flutter build
  /// [command]` writes in intermediate directories and copies into its
  /// products from there.
  ///
  /// Only intermediate copies are listed. Finished products, including other
  /// platforms' (e.g. an .xcarchive or a Linux bundle), are left alone.
  List<File> _generatedShorebirdYamls(String command) {
    final projectRoot = shorebirdEnv.getFlutterProjectRoot()!;
    final buildDirectory = shorebirdEnv.buildDirectory;
    return switch (command) {
      // Each Gradle project of an app builds into build/<project name>.
      'apk' || 'appbundle' => [
        for (final gradleBuildDirectory in _subdirectories(buildDirectory))
          ..._gradleGeneratedShorebirdYamls(gradleBuildDirectory),
      ],
      // A module's Flutter Gradle project builds into .android/Flutter/build.
      'aar' => _gradleGeneratedShorebirdYamls(
        Directory(p.join(projectRoot.path, '.android', 'Flutter', 'build')),
      ),
      // `flutter assemble --output=build`, which the CMake install step copies
      // into the bundle.
      'linux' || 'windows' => [
        File(p.join(buildDirectory.path, 'flutter_assets', 'shorebird.yaml')),
      ],
      // Apple builds delete Flutter's build cache instead, see
      // [_buildAppleKernel].
      _ => const [],
    };
  }

  /// The generated shorebird.yaml that the Flutter Gradle task wrote for each
  /// build variant of the Gradle project building into [gradleBuildDirectory].
  /// Gradle copies it into the archive from there.
  List<File> _gradleGeneratedShorebirdYamls(Directory gradleBuildDirectory) {
    final flutterIntermediates = Directory(
      p.join(gradleBuildDirectory.path, 'intermediates', 'flutter'),
    );
    return [
      for (final variantDirectory in _subdirectories(flutterIntermediates))
        File(p.join(variantDirectory.path, 'flutter_assets', 'shorebird.yaml')),
    ];
  }

  /// The directories directly inside [directory], or none if it does not
  /// exist.
  List<Directory> _subdirectories(Directory directory) {
    if (!directory.existsSync()) return const [];
    return directory.listSync().whereType<Directory>().toList();
  }

  /// Runs an Apple `flutter build [command]` (see [_runFlutterBuild]) and
  /// returns the app.dill it produced.
  Future<AppleBuildResult> _buildAppleKernel({
    required String command,
    required String description,
    required List<String> flags,
    required List<String> args,
    required String? base64PublicKey,
    required int? ddMaxBytes,
  }) async {
    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    // Delete Flutter's build cache so every target re-runs. We look for a
    // recently modified app.dill, which a skipped kernel step would not write.
    // A cached build would also be stale here: the SHOREBIRD_PUBLIC_KEY and
    // (on iOS only; the macOS DD pass is skipped) SHOREBIRD_DD_MAX_BYTES
    // environment variables change the build's output but are not inputs
    // Flutter's build system tracks.
    final flutterBuildDir = _flutterBuildDirectory(projectRoot);
    if (flutterBuildDir.existsSync()) {
      flutterBuildDir.deleteSync(recursive: true);
    }
    // Delete .dart_tool/version so `flutter build` runs `pub get` with
    // Shorebird's Flutter. After the previous build we reset
    // package_config.json with the system Flutter (see
    // [_runShorebirdBuildCommand]), and Flutter skips `pub get` when this file
    // matches its version, which can be shared by several Flutter checkouts.
    // The rest of .dart_tool (build_runner and native asset caches) is kept.
    final dartToolVersionFile = File(
      p.join(projectRoot.path, '.dart_tool', 'version'),
    );
    if (dartToolVersionFile.existsSync()) {
      dartToolVersionFile.deleteSync();
    }

    String? appDillPath;
    await _runShorebirdBuildCommand(() async {
      final buildStart = await _runFlutterBuild(
        command: command,
        description: description,
        flags: flags,
        args: args,
        base64PublicKey: base64PublicKey,
        ddMaxBytes: ddMaxBytes,
      );
      appDillPath = _findAppDill(projectRoot: projectRoot, after: buildStart);
    });

    if (appDillPath == null) {
      throw ArtifactBuildException(
        'Unable to find app.dill file.',
        fixRecommendation:
            '''Please file a bug at https://github.com/shorebirdtech/shorebird/issues/new with the logs for this command.''',
      );
    }

    return AppleBuildResult(kernelFile: File(appDillPath!));
  }

  /// Returns the artifact found by [find], turning a missing or ambiguous
  /// [name] (e.g. "AAB") into an [ArtifactBuildException].
  File _findBuiltArtifact(String name, File Function() find) {
    try {
      return find();
    } on MultipleArtifactsFoundException catch (error) {
      throw ArtifactBuildException(
        'Build succeeded, but it generated multiple ${name}s in the '
        'build directory. ${error.foundArtifacts.map((e) => e.path)}',
      );
    } on ArtifactNotFoundException catch (error) {
      throw ArtifactBuildException(
        'Build succeeded, but could not find the $name in the build directory. '
        'Expected to find ${error.artifactName}',
      );
    }
  }

  /// Prepares build tracing for the current command invocation. Populates
  /// [BuildTraceSession.traceFile] and [BuildTraceSession.platform] so that
  /// downstream `flutter build`, `aot_tools`, and gen_snapshot calls can
  /// emit into the same trace file — and so [writeBuildTraceSummary] can
  /// pick up the right platform later.
  ///
  /// Call from the outer `release_command` / `patch_command` once per
  /// platform, *after* the target Flutter revision has been installed and
  /// the `shorebirdEnv` override is active so the version gate checks the
  /// correct revision.
  ///
  /// No-op on older Flutter pins that don't support `--shorebird-trace`
  /// (leaves session fields null → builders emit no tracing args).
  Future<void> prepareBuildTrace({required String platform}) async {
    buildTraceSession.platform = platform;
    final revision = shorebirdEnv.flutterRevision;
    final flutterVersion = await shorebirdFlutter.resolveFlutterVersion(
      revision,
    );
    // Treat an unknown version (e.g. a pinned dev revision) as new enough,
    // matching the pattern used for other version-gated features.
    final supportsTrace = buildTraceSupportConstraint.isSatisfiedBy(
      version: flutterVersion ?? buildTraceSupportConstraint.minVersion,
      revision: revision,
    );
    if (!supportsTrace) {
      buildTraceSession.traceFile = null;
      return;
    }

    final traceFile = File(
      p.join(
        shorebirdEnv.buildDirectory.path,
        'shorebird',
        'debug',
        'build-trace-$platform.json',
      ),
    );
    traceFile.parent.createSync(recursive: true);
    buildTraceSession.traceFile = traceFile;
  }

  /// Emits a flow-start event (`ph: "s"`) on the shorebird_cli tracer
  /// tied to the spawned flutter process's real pid. When flutter builds
  /// with `--shorebird-trace`, it records a flow-end with its own pid as
  /// the flow id — Perfetto draws an arrow from our spawn point into
  /// flutter's first span.
  void _emitFlutterSpawnFlow(Process flutter) {
    shorebirdTracer.addSpawnFlowStart(id: flutter.pid, at: clock.now());
  }

  /// Returns the user's home directory as understood by the OS, or
  /// null if neither `HOME` nor `USERPROFILE` is set. Reads from the
  /// scoped `platform` (same pattern as e.g. `android_studio.dart`)
  /// rather than static `Platform.environment` so tests can inject a
  /// fake environment.
  Directory? _homeDirectory() {
    final env = scoped_platform.platform.environment;
    final h = env['HOME'] ?? env['USERPROFILE'];
    if (h == null || h.isEmpty) return null;
    return Directory(h);
  }

  /// Writes a privacy-safe summary JSON (`build-trace-<platform>-summary.json`)
  /// next to [BuildTraceSession.traceFile]. Best-effort: logs at detail level
  /// on failure. Caches the parsed summary on [BuildTraceSession.summary] so
  /// `release_command` / `patch_command` can attach it to the outgoing
  /// metadata blob without re-parsing the trace file.
  ///
  /// Uses [BuildTraceSession.commandStartedAt] to derive the wall-clock time
  /// Shorebird itself spent around the Flutter build, subtracting Flutter's
  /// reported total (the "flutter build X" umbrella event).
  ///
  /// Call from the outer `release_command` / `patch_command` *after* all
  /// post-flutter-build work (aot_tools, gen_snapshot, artifact uploads) has
  /// completed, so their events are included in the aggregates.
  void writeBuildTraceSummary() {
    final traceFile = buildTraceSession.traceFile;
    final buildPlatform = buildTraceSession.platform;
    if (traceFile == null || buildPlatform == null) return;

    // Merge Shorebird-side events (HTTP calls, subprocess spans, phase
    // markers accumulated since `main()`) into Flutter's trace file so
    // both local Perfetto viewing and the aggregate summary see the
    // complete picture.
    shorebirdTracer.mergeInto(traceFile);

    final events = BuildTraceSummary.tryReadEvents(traceFile);
    if (events == null) {
      logger.detail(
        'Skipping build trace summary: ${traceFile.path} missing or malformed.',
      );
      return;
    }

    // First pass: measure Flutter's reported build wall clock so we can
    // derive Shorebird's overhead. Second pass (below) then bakes overhead
    // and environment into the final summary. Parsed events are reused so
    // the (often multi-megabyte) trace file is only read once.
    final flutterBuild = BuildTraceSummary.fromEvents(
      events,
      platform: buildPlatform,
    ).flutterBuild;
    final totalElapsed = DateTime.now().difference(
      buildTraceSession.commandStartedAt,
    );
    final shorebirdOverhead = totalElapsed - flutterBuild;
    // Snapshot the build environment (caching config, CI provider, ...).
    // This is what lets us tell, in field data, whether a slow build is
    // "no caching configured" vs "slow despite caching being on".
    final environment = BuildEnvironment.detect(
      environment: scoped_platform.platform.environment,
      homeDir: _homeDirectory(),
      projectRoot: shorebirdEnv.getShorebirdProjectRoot(),
    );
    // If the trace reports a longer build than the command has been running
    // (clock skew, malformed trace), treat overhead as zero rather than
    // negative.
    final summary = BuildTraceSummary.fromEvents(
      events,
      platform: buildPlatform,
      shorebirdOverhead: shorebirdOverhead.isNegative
          ? Duration.zero
          : shorebirdOverhead,
      environment: environment,
    );

    // Cache for the release/patch metadata uploader to read without
    // re-parsing the trace file.
    buildTraceSession.summary = summary;

    final summaryPath = p.join(
      p.dirname(traceFile.path),
      'build-trace-$buildPlatform-summary.json',
    );
    File(summaryPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(summary.toJson()),
    );
    logger.detail('Build trace summary written to $summaryPath');
  }

  /// A wrapper around [command] (which runs a `flutter build` command with
  /// Shorebird's fork of Flutter) with a try/finally that runs
  /// `flutter pub get` with the system installation of Flutter to reset
  /// `.dart_tool/package_config.json` to the system Flutter.
  Future<void> _runShorebirdBuildCommand(ShorebirdBuildCommand command) async {
    try {
      await command();
    } finally {
      await _systemFlutterPubGet();
    }
  }

  /// This is a hack to reset `.dart_tool/package_config.json` to point to the
  /// Flutter SDK on the user's PATH. This is necessary because Flutter commands
  /// run by shorebird update the package_config.json file to point to
  /// shorebird's version of Flutter, which confuses VS Code. See
  /// https://github.com/shorebirdtech/shorebird/issues/1101 for more info.
  Future<void> _systemFlutterPubGet() async {
    const executable = 'flutter';
    if (osInterface.which(executable) == null) {
      // If the user doesn't have Flutter on their PATH, then we can't run
      // `flutter pub get` with the system Flutter.
      return;
    }

    final arguments = ['--no-version-check', 'pub', 'get', '--offline'];

    final result = await process.run(
      executable,
      arguments,
      useVendedFlutter: false,
    );

    if (result.exitCode != ExitCode.success.code) {
      logger.warn('''
Build was successful, but `flutter pub get` failed to run after the build completed. You may see unexpected behavior in VS Code.

Either run `flutter pub get` manually, or follow the steps in ${cannotRunInVSCodeUrl.toLink()}.
''');
    }
  }

  /// Creates an AOT snapshot of the given [appDillPath] at [outFilePath] and
  /// returns the resulting file.
  Future<File> buildElfAotSnapshot({
    required String appDillPath,
    required String outFilePath,
    required ShorebirdArtifact genSnapshotArtifact,
    List<String> additionalArgs = const [],
  }) async {
    final arguments = [
      '--deterministic',
      '--snapshot-kind=app-aot-elf',
      '--elf=$outFilePath',
      ...additionalArgs,
      appDillPath,
    ];

    // Record a span on the shorebird_cli row so gen_snapshot time shows up
    // in Perfetto and rolls into the trace summary's subprocess bucket.
    // gen_snapshot itself doesn't emit a trace; this is the best signal we
    // have for how long native codegen took during patching.
    final exitCode = await shorebirdTracer.span<int>(
      name: 'gen_snapshot',
      category: 'subprocess',
      body: () => process.stream(
        shorebirdArtifacts.getArtifactPath(artifact: genSnapshotArtifact),
        arguments,
        // Never run in shell because we always have a fully resolved
        // executable path.
        runInShell: false,
      ),
    );

    if (exitCode != ExitCode.success.code) {
      throw ArtifactBuildException('Failed to create snapshot');
    }

    return File(outFilePath);
  }

  /// Builds a windows app and returns the x64 Release directory
  Future<Directory> buildWindowsApp({
    String? target,
    List<String> args = const [],
    String? base64PublicKey,
    int? ddMaxBytes,
  }) async {
    await _runShorebirdBuildCommand(
      () => _runFlutterBuild(
        command: 'windows',
        description: 'windows app',
        flags: ['--release', if (target != null) '--target=$target'],
        args: args,
        base64PublicKey: base64PublicKey,
        ddMaxBytes: ddMaxBytes,
      ),
    );

    return artifactManager.getWindowsReleaseDirectory();
  }

  /// The directory under [projectRoot] where Flutter's build system keeps its
  /// cache and intermediate outputs, including app.dill.
  Directory _flutterBuildDirectory(Directory projectRoot) =>
      Directory(p.join(projectRoot.path, '.dart_tool', 'flutter_build'));

  /// Finds the app.dill file generated during the build process. Looks in the
  /// .dart_tool/flutter_build directory of the provided [projectRoot] (Flutter
  /// writes it to `flutter_build/<build hash>/app.dill`) for app.dill files
  /// modified after [after] and returns the path of the earliest one, or null
  /// if there is none.
  ///
  /// The earliest is the first one the build produced. A build can produce
  /// more than one (e.g. `ios-framework` builds more than one target), and
  /// this matches the behavior from before app.dill was found on disk, when
  /// the first `gen_snapshot ... app.dill` line in the build output was used.
  String? _findAppDill({
    required Directory projectRoot,
    required DateTime after,
  }) {
    final flutterBuildDir = _flutterBuildDirectory(projectRoot);
    if (!flutterBuildDir.existsSync()) return null;
    return flutterBuildDir
        .listSync(recursive: true)
        .where(
          (e) =>
              e is File &&
              p.basename(e.path) == 'app.dill' &&
              e.statSync().modified.isAfter(after),
        )
        .sortedBy((e) => e.statSync().modified)
        .firstOrNull
        ?.path;
  }
}

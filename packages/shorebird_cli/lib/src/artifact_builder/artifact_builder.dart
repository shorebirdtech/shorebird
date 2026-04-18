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

extension on String {
  /// Converts this base64-encoded public key into the `Map<String, String>`:
  ///   {'SHOREBIRD_PUBLIC_KEY': this}
  ///
  /// SHOREBIRD_PUBLIC_KEY is the name expected by the Shorebird's Flutter tool
  ///
  /// This allow us to just call var?.toPublicKeyEnv() instead of doing
  /// a ternary operation to check if the value is null.
  Map<String, String> toPublicKeyEnv() => {'SHOREBIRD_PUBLIC_KEY': this};
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

  /// Builds an aab using `flutter build appbundle`. Runs `flutter pub get` with
  /// the system installation of Flutter to reset
  /// `.dart_tool/package_config.json` after the build completes or fails.
  Future<File> buildAppBundle({
    String? flavor,
    String? target,
    Iterable<Arch>? targetPlatforms,
    List<String> args = const [],
    String? base64PublicKey,
  }) async {
    await _runShorebirdBuildCommand(() async {
      const executable = 'flutter';
      final targetPlatformArgs = targetPlatforms?.targetPlatformArg;
      final traceFile = await _prepareBuildTrace(platform: 'android');
      final arguments = [
        'build',
        'appbundle',
        '--release',
        if (flavor != null) '--flavor=$flavor',
        if (target != null) '--target=$target',
        if (targetPlatformArgs != null) '--target-platform=$targetPlatformArgs',
        if (traceFile != null) '--shorebird-trace=${traceFile.path}',
        ...args,
      ];

      final exitCode = await process.stream(
        executable,
        arguments,
        environment: base64PublicKey?.toPublicKeyEnv(),
        // Never run in shell because we always have a fully resolved
        // executable path.
        runInShell: false,
        onStart: _emitFlutterSpawnFlow,
      );

      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          '''
Failed to build AAB.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''',
          fixRecommendation: runVanillaFlutterBuildRecommendation(
            [executable, ...arguments].join(' '),
          ),
        );
      }

      _writeBuildTraceSummary(traceFile, buildPlatform: 'android');
    });

    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    try {
      return shorebirdAndroidArtifacts.findAab(
        project: projectRoot,
        flavor: flavor,
      );
    } on MultipleArtifactsFoundException catch (error) {
      throw ArtifactBuildException(
        'Build succeeded, but it generated multiple AABs in the '
        'build directory. ${error.foundArtifacts.map((e) => e.path)}',
      );
    } on ArtifactNotFoundException catch (error) {
      throw ArtifactBuildException(
        'Build succeeded, but could not find the AAB in the build directory. '
        'Expected to find ${error.artifactName}',
      );
    }
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
  }) async {
    await _runShorebirdBuildCommand(() async {
      const executable = 'flutter';
      final targetPlatformArgs = targetPlatforms?.targetPlatformArg;
      final traceFile = await _prepareBuildTrace(platform: 'android');
      final arguments = [
        'build',
        'apk',
        '--release',
        if (flavor != null) '--flavor=$flavor',
        if (target != null) '--target=$target',
        if (targetPlatformArgs != null) '--target-platform=$targetPlatformArgs',
        // TODO(bryanoltman): reintroduce coverage when we can support this.
        // See https://github.com/shorebirdtech/shorebird/issues/1141.
        // coverage:ignore-start
        if (splitPerAbi) '--split-per-abi',
        // coverage:ignore-end
        if (traceFile != null) '--shorebird-trace=${traceFile.path}',
        ...args,
      ];

      final exitCode = await process.stream(
        executable,
        arguments,
        environment: base64PublicKey?.toPublicKeyEnv(),
        // Never run in shell because we always have a fully resolved
        // executable path.
        runInShell: false,
        onStart: _emitFlutterSpawnFlow,
      );

      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          '''
Failed to build APK.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''',
          fixRecommendation: runVanillaFlutterBuildRecommendation(
            [executable, ...arguments].join(' '),
          ),
        );
      }

      _writeBuildTraceSummary(traceFile, buildPlatform: 'android');
    });
    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    try {
      return shorebirdAndroidArtifacts.findApk(
        project: projectRoot,
        flavor: flavor,
      );
    } on MultipleArtifactsFoundException catch (error) {
      throw ArtifactBuildException(
        'Build succeeded, but it generated multiple APKs in the '
        'build directory. ${error.foundArtifacts.map((e) => e.path)}',
      );
    } on ArtifactNotFoundException catch (error) {
      throw ArtifactBuildException(
        'Build succeeded, but could not find the APK in the build directory. '
        'Expected to find ${error.artifactName}',
      );
    }
  }

  /// Builds an AAR using `flutter build aar`. Runs `flutter pub get` with the
  /// system installation of Flutter to reset `.dart_tool/package_config.json`
  /// after the build completes or fails.
  Future<void> buildAar({
    required String buildNumber,
    Iterable<Arch>? targetPlatforms,
    List<String> args = const [],
    String? base64PublicKey,
  }) async {
    return _runShorebirdBuildCommand(() async {
      const executable = 'flutter';
      final targetPlatformArgs = targetPlatforms?.targetPlatformArg;
      final arguments = [
        'build',
        'aar',
        '--no-debug',
        '--no-profile',
        '--build-number=$buildNumber',
        if (targetPlatformArgs != null) '--target-platform=$targetPlatformArgs',
        ...args,
      ];

      final exitCode = await process.stream(
        executable,
        arguments,
        environment: base64PublicKey?.toPublicKeyEnv(),
        // Never run in shell because we always have a fully resolved
        // executable path.
        runInShell: false,
      );

      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          '''
Failed to build AAR.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''',
          fixRecommendation: runVanillaFlutterBuildRecommendation(
            [executable, ...arguments].join(' '),
          ),
        );
      }
    });
  }

  /// Builds a Linux desktop application by running `flutter build linux
  /// --release` with Shorebird's fork of Flutter.
  Future<void> buildLinuxApp({
    String? target,
    List<String> args = const [],
    String? base64PublicKey,
  }) async {
    await _runShorebirdBuildCommand(() async {
      const executable = 'flutter';
      final arguments = [
        'build',
        'linux',
        '--release',
        if (target != null) '--target=$target',
        ...args,
      ];

      final exitCode = await process.stream(
        executable,
        arguments,
        environment: base64PublicKey?.toPublicKeyEnv(),
        // Never run in shell because we always have a fully resolved
        // executable path.
        runInShell: false,
      );

      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          '''
Failed to build linux app.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''',
          fixRecommendation: runVanillaFlutterBuildRecommendation(
            [executable, ...arguments].join(' '),
          ),
        );
      }
    });
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
  }) async {
    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    // Delete the .dart_tool directory to ensure that the app is rebuilt. This
    // is necessary because we always look for a recently modified app.dill.
    final dartToolDir = Directory(p.join(projectRoot.path, '.dart_tool'));
    if (dartToolDir.existsSync()) {
      dartToolDir.deleteSync(recursive: true);
    }
    String? appDillPath;
    await _runShorebirdBuildCommand(() async {
      const executable = 'flutter';
      final arguments = [
        'build',
        'macos',
        '--release',
        if (flavor != null) '--flavor=$flavor',
        if (target != null) '--target=$target',
        if (!codesign) '--no-codesign',
        ...args,
      ];
      final buildStart = clock.now();
      final exitCode = await process.stream(
        executable,
        arguments,
        environment: base64PublicKey?.toPublicKeyEnv(),
        // Never run in shell because we always have a fully resolved
        // executable path.
        runInShell: false,
      );

      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          '''
Failed to build macOS app.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''',
          fixRecommendation: runVanillaFlutterBuildRecommendation(
            [executable, ...arguments].join(' '),
          ),
        );
      }

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

  /// Calls `flutter build ipa`. If [codesign] is false, this will only build
  /// an .xcarchive and _not_ an .ipa.
  Future<AppleBuildResult> buildIpa({
    bool codesign = true,
    String? flavor,
    String? target,
    List<String> args = const [],
    String? base64PublicKey,
  }) async {
    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    // Delete the .dart_tool directory to ensure that the app is rebuilt. This
    // is necessary because we always look for a recently modified app.dill.
    final dartToolDir = Directory(p.join(projectRoot.path, '.dart_tool'));
    if (dartToolDir.existsSync()) {
      dartToolDir.deleteSync(recursive: true);
    }

    String? appDillPath;
    await _runShorebirdBuildCommand(() async {
      const executable = 'flutter';
      final traceFile = await _prepareBuildTrace(platform: 'ios');
      final arguments = [
        'build',
        'ipa',
        '--release',
        if (flavor != null) '--flavor=$flavor',
        if (target != null) '--target=$target',
        if (!codesign) '--no-codesign',
        if (traceFile != null) '--shorebird-trace=${traceFile.path}',
        ...args,
      ];

      final buildStart = clock.now();
      final exitCode = await process.stream(
        executable,
        arguments,
        environment: base64PublicKey?.toPublicKeyEnv(),
        // Never run in shell because we always have a fully resolved
        // executable path.
        runInShell: false,
        onStart: _emitFlutterSpawnFlow,
      );

      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          '''
Failed to build IPA.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''',
          fixRecommendation: runVanillaFlutterBuildRecommendation(
            [executable, ...arguments].join(' '),
          ),
        );
      }

      _writeBuildTraceSummary(traceFile, buildPlatform: 'ios');
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

  /// Builds a release iOS framework (.xcframework) for the current project.
  Future<AppleBuildResult> buildIosFramework({
    List<String> args = const [],
    String? base64PublicKey,
  }) async {
    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    // Delete the .dart_tool directory to ensure that the app is rebuilt. This
    // is necessary because we always look for a recently modified app.dill.
    final dartToolDir = Directory(p.join(projectRoot.path, '.dart_tool'));
    if (dartToolDir.existsSync()) {
      dartToolDir.deleteSync(recursive: true);
    }
    String? appDillPath;
    await _runShorebirdBuildCommand(() async {
      const executable = 'flutter';
      final arguments = [
        'build',
        'ios-framework',
        '--no-debug',
        '--no-profile',
        ...args,
      ];

      final buildStart = clock.now();
      final exitCode = await process.stream(
        executable,
        arguments,
        environment: base64PublicKey?.toPublicKeyEnv(),
        // Never run in shell because we always have a fully resolved
        // executable path.
        runInShell: false,
      );

      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          '''
Failed to build iOS framework.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''',
          fixRecommendation: runVanillaFlutterBuildRecommendation(
            [executable, ...arguments].join(' '),
          ),
        );
      }

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

  /// Prepares build tracing for a `flutter build` invocation.
  ///
  /// Returns the trace file path (if tracing is supported on the pinned
  /// Flutter) so the caller can both inject `--shorebird-trace=<path>` and,
  /// after the build succeeds, emit a privacy-safe summary next to it.
  Future<File?> _prepareBuildTrace({required String platform}) async {
    final flutterVersion = await shorebirdFlutter.resolveFlutterVersion(
      shorebirdEnv.flutterRevision,
    );
    // Treat an unknown version (e.g. a pinned dev revision) as new enough,
    // matching the pattern used for other version-gated features.
    final supportsTrace =
        (flutterVersion ?? minimumBuildTraceFlutterVersion) >=
        minimumBuildTraceFlutterVersion;
    if (!supportsTrace) return null;

    final traceFile = File(
      p.join(
        shorebirdEnv.buildDirectory.path,
        'shorebird',
        'debug',
        'build-trace-$platform.json',
      ),
    );
    traceFile.parent.createSync(recursive: true);
    return traceFile;
  }

  /// Emits a flow-start event (`ph: "s"`) on the shorebird_cli tracer
  /// tied to the spawned flutter process's real pid. When flutter builds
  /// with `--shorebird-trace`, it records a flow-end with its own pid as
  /// the flow id — Perfetto draws an arrow from our spawn point into
  /// flutter's first span.
  void _emitFlutterSpawnFlow(Process flutter) {
    shorebirdTracer.addSpawnFlowStart(
      id: flutter.pid,
      atMicros: DateTime.now().microsecondsSinceEpoch,
    );
  }

  /// Returns the user's home directory as understood by the OS, or
  /// null if neither `HOME` nor `USERPROFILE` is set. Reads from the
  /// scoped [platform] (same pattern as e.g. `android_studio.dart`)
  /// rather than static `Platform.environment` so tests can inject a
  /// fake environment.
  Directory? _homeDirectory() {
    final env = scoped_platform.platform.environment;
    final h = env['HOME'] ?? env['USERPROFILE'];
    if (h == null || h.isEmpty) return null;
    return Directory(h);
  }

  /// Writes a privacy-safe summary JSON (`build-trace-<platform>-summary.json`)
  /// next to [traceFile]. Best-effort: logs at detail level on failure.
  ///
  /// Uses [BuildTraceSession.commandStartedAt] to derive the wall-clock time
  /// Shorebird itself spent around the Flutter build, subtracting Flutter's
  /// reported total (the "flutter build X" umbrella event).
  void _writeBuildTraceSummary(
    File? traceFile, {
    required String buildPlatform,
  }) {
    if (traceFile == null) return;

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

    final exitCode = await process.stream(
      shorebirdArtifacts.getArtifactPath(artifact: genSnapshotArtifact),
      arguments,
      // Never run in shell because we always have a fully resolved
      // executable path.
      runInShell: false,
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
  }) async {
    await _runShorebirdBuildCommand(() async {
      const executable = 'flutter';
      final arguments = [
        'build',
        'windows',
        '--release',
        if (target != null) '--target=$target',
        ...args,
      ];

      final exitCode = await process.stream(
        executable,
        arguments,
        environment: base64PublicKey?.toPublicKeyEnv(),
        // Never run in shell because we always have a fully resolved
        // executable path.
        runInShell: false,
      );

      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          '''
Failed to build windows app.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''',
          fixRecommendation: runVanillaFlutterBuildRecommendation(
            [executable, ...arguments].join(' '),
          ),
        );
      }
    });

    return artifactManager.getWindowsReleaseDirectory();
  }

  /// Finds the app.dill file generated during the build process. Looks in the
  /// .dart_tool directory of the provided [projectRoot] for the most recently
  /// modified app.dill file (newer than [after]). Returns the path to the
  /// app.dill file, or null if no app.dill file is found.
  String? _findAppDill({
    required Directory projectRoot,
    required DateTime after,
  }) {
    final dartToolDirectory = Directory(p.join(projectRoot.path, '.dart_tool'));
    if (!dartToolDirectory.existsSync()) return null;
    return dartToolDirectory
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

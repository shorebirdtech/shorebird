// cspell:words endtemplate aabs ipas appbundle bryanoltman codesign xcarchive
// cspell:words xcframework
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_build_exception.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

export 'artifact_build_exception.dart';

/// Used to wrap code that invokes `flutter build` with Shorebird's fork of
/// Flutter.
typedef ShorebirdBuildCommand = Future<void> Function();

// TODO(bryanoltman): The following three apple BuildResult classes are
// identical and should be merged. They are all capturing the idea that we want
// to get the kernel (app.dill) file generated during a build so we can use it
// to link when patching.

/// {@template ipa_build_result}
/// Metadata about the result of a `flutter build ipa` invocation.
/// {@endtemplate}
class IpaBuildResult {
  /// {@macro ipa_build_result}
  IpaBuildResult({required this.kernelFile});

  /// The app.dill file produced by this invocation of `flutter build ipa`.
  final File kernelFile;
}

/// {@template ios_framework_build_result}
/// Metadata about the result of a `flutter build ios-framework` invocation.
/// {@endtemplate}
class IosFrameworkBuildResult {
  /// {@macro ios_framework_build_result}
  IosFrameworkBuildResult({required this.kernelFile});

  /// The app.dill file produced by this invocation of `flutter build ipa`.
  final File kernelFile;
}

/// {@template macos_build_result}
/// Metadata about the result of a `flutter build macos` invocation.
/// {@endtemplate}
class MacosBuildResult {
  /// {@macro macos_build_result}
  MacosBuildResult({required this.kernelFile});

  /// The app.dill file produced by this invocation of `flutter build ipa`.
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
  /// Builds an aab using `flutter build appbundle`. Runs `flutter pub get` with
  /// the system installation of Flutter to reset
  /// `.dart_tool/package_config.json` after the build completes or fails.
  Future<File> buildAppBundle({
    String? flavor,
    String? target,
    Iterable<Arch>? targetPlatforms,
    List<String> args = const [],
    String? base64PublicKey,
    DetailProgress? buildProgress,
  }) async {
    await _runShorebirdBuildCommand(() async {
      const executable = 'flutter';
      final targetPlatformArgs = targetPlatforms?.targetPlatformArg;
      final arguments = [
        'build',
        'appbundle',
        '--release',
        if (flavor != null) '--flavor=$flavor',
        if (target != null) '--target=$target',
        if (targetPlatformArgs != null) '--target-platform=$targetPlatformArgs',
        ...args,
      ];

      final buildProcess = await process.stream(
        executable,
        arguments,
        environment: base64PublicKey?.toPublicKeyEnv(),
        progress: buildProgress,
      );

      final exitCode = buildProcess.exitCode;
      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          '''
Failed to build AAB.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''',
          stderr: '${buildProcess.stderr}'.split('\n'),
          stdout: '${buildProcess.stdout}'.split('\n'),
        );
      }
    });

    // If we've been updating the progress with gradle tasks, reset it to the
    // original base message so as not to leave the user with a confusing
    // message.
    buildProgress?.updateDetailMessage(null);

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
        ...args,
      ];

      final result = await process.stream(
        executable,
        arguments,
        environment: base64PublicKey?.toPublicKeyEnv(),
      );

      if (result.exitCode != ExitCode.success.code) {
        throw ArtifactBuildException.fromProcessResult('''
Failed to build APK.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''', buildProcessResult: result);
      }
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

      final result = await process.stream(executable, arguments);

      if (result.exitCode != ExitCode.success.code) {
        throw ArtifactBuildException.fromProcessResult('''
Failed to build AAR.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''', buildProcessResult: result);
      }
    });
  }

  /// Builds a Linux desktop application by running `flutter build linux
  /// --release` with Shorebird's fork of Flutter.
  Future<void> buildLinuxApp({
    String? target,
    List<String> args = const [],
    String? base64PublicKey,
    DetailProgress? buildProgress,
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

      final buildProcess = await process.stream(
        executable,
        arguments,
        environment: base64PublicKey?.toPublicKeyEnv(),
        progress: buildProgress,
      );

      final exitCode = buildProcess.exitCode;
      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          '''
Failed to build linux app.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''',
          stdout: '${buildProcess.stdout}'.split('\n'),
          stderr: '${buildProcess.stderr}'.split('\n'),
        );
      }
    });
  }

  /// Builds a macOS app using `flutter build macos`. Runs `flutter pub get`
  /// with the system installation of Flutter to reset
  /// `.dart_tool/package_config.json` after the build completes or fails.
  Future<MacosBuildResult> buildMacos({
    bool codesign = true,
    String? flavor,
    String? target,
    List<String> args = const [],
    String? base64PublicKey,
    DetailProgress? buildProgress,
  }) async {
    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    // Delete the .dart_tool directory to ensure that the app is rebuilt.
    // Without this, the build command will not print the app.dill path
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

      final buildProcess = await process.stream(
        executable,
        arguments,
        environment: base64PublicKey?.toPublicKeyEnv(),
        progress: buildProgress,
        evalOutput: true,
      );

      final exitCode = buildProcess.exitCode;
      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          '''
Failed to build macOS app.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''',
          stdout: '${buildProcess.stdout}'.split('\n'),
          stderr: '${buildProcess.stderr}'.split('\n'),
        );
      }

      appDillPath = findAppDill(stdout: '${buildProcess.stdout}');
    });

    if (appDillPath == null) {
      throw ArtifactBuildException(
        'Unable to find app.dill file.',
        fixRecommendation:
            '''Please file a bug at https://github.com/shorebirdtech/shorebird/issues/new with the logs for this command.''',
      );
    }

    return MacosBuildResult(kernelFile: File(appDillPath!));
  }

  /// Calls `flutter build ipa`. If [codesign] is false, this will only build
  /// an .xcarchive and _not_ an .ipa.
  Future<IpaBuildResult> buildIpa({
    bool codesign = true,
    String? flavor,
    String? target,
    List<String> args = const [],
    String? base64PublicKey,
    DetailProgress? buildProgress,
  }) async {
    String? appDillPath;
    await _runShorebirdBuildCommand(() async {
      const executable = 'flutter';
      final arguments = [
        'build',
        'ipa',
        '--release',
        if (flavor != null) '--flavor=$flavor',
        if (target != null) '--target=$target',
        if (!codesign) '--no-codesign',
        ...args,
      ];

      final buildProcess = await process.stream(
        executable,
        arguments,
        environment: base64PublicKey?.toPublicKeyEnv(),
        progress: buildProgress,
        evalOutput: true,
      );

      final stdout = '${buildProcess.stdout}';
      final stdoutLines = stdout.split('\n');

      final stderr = '${buildProcess.stderr}';
      final stderrLines = stderr.split('\n');

      // If we've been updating the progress, reset it to the original base
      // message so as not to leave the user with a confusing message.
      buildProgress?.updateDetailMessage(null);

      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          '''
Failed to build IPA.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.''',
          stdout: stdoutLines,
          stderr: stderrLines,
        );
      }

      // TODO(bryanoltman): this is not treated as an error by Flutter.
      // We should not throw here, see:
      // https://github.com/shorebirdtech/shorebird/issues/2855
      if (stderr.contains('Encountered error while creating the IPA')) {
        throw ArtifactBuildException(
          '''
Failed to build IPA.
Command: $executable ${arguments.join(' ')}
Reason: stderr contains "Encountered error while creating the IPA".''',
          stdout: stdoutLines,
          stderr: stderrLines,
        );
      }

      appDillPath = findAppDill(stdout: stdout);
    });

    if (appDillPath == null) {
      throw ArtifactBuildException(
        'Unable to find app.dill file.',
        fixRecommendation:
            '''Please file a bug at https://github.com/shorebirdtech/shorebird/issues/new with the logs for this command.''',
      );
    }

    return IpaBuildResult(kernelFile: File(appDillPath!));
  }

  /// Builds a release iOS framework (.xcframework) for the current project.
  Future<IosFrameworkBuildResult> buildIosFramework({
    List<String> args = const [],
  }) async {
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

      final result = await process.stream(
        executable,
        arguments,
        evalOutput: true,
      );

      if (result.exitCode != ExitCode.success.code) {
        throw ArtifactBuildException('''
Failed to build iOS framework.
Command: $executable ${arguments.join(' ')}
Reason: Exited with code $exitCode.
''');
      }

      appDillPath = findAppDill(stdout: result.stdout.toString());
    });

    if (appDillPath == null) {
      throw ArtifactBuildException(
        'Unable to find app.dill file.',
        fixRecommendation:
            '''Please file a bug at https://github.com/shorebirdtech/shorebird/issues/new with the logs for this command.''',
      );
    }

    return IosFrameworkBuildResult(kernelFile: File(appDillPath!));
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

    final result = await process.stream(
      shorebirdArtifacts.getArtifactPath(artifact: genSnapshotArtifact),
      arguments,
    );

    if (result.exitCode != ExitCode.success.code) {
      throw ArtifactBuildException.fromProcessResult(
        'Failed to create snapshot',
        buildProcessResult: result,
      );
    }

    return File(outFilePath);
  }

  /// Builds a windows app and returns the x64 Release directory
  Future<Directory> buildWindowsApp({
    String? flavor,
    String? target,
    List<String> args = const [],
    String? base64PublicKey,
    DetailProgress? buildProgress,
  }) async {
    await _runShorebirdBuildCommand(() async {
      const executable = 'flutter';
      final arguments = ['build', 'windows', '--release', ...args];

      final buildProcess = await process.stream(
        executable,
        arguments,
        environment: base64PublicKey?.toPublicKeyEnv(),
      );

      final exitCode = buildProcess.exitCode;
      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          'Failed to build',
          stderr: '${buildProcess.stderr}'.split('\n'),
          stdout: '${buildProcess.stdout}'.split('\n'),
        );
      }
    });

    return artifactManager.getWindowsReleaseDirectory();
  }

  /// Given the full stdout from a `flutter build ipa` or `flutter build macos`
  /// command, finds the path to the app.dill file that was built.
  @visibleForTesting
  String? findAppDill({required String stdout}) {
    final appDillLine = stdout
        .split('\n')
        .firstWhereOrNull(
          (l) => l.contains('gen_snapshot') && l.endsWith('app.dill'),
        );

    if (appDillLine == null) return null;

    // The last argument in the line is the path to app.dill. Because
    //   1) paths can contain spaces and
    //   2) the path to the app.dill is absolute (i.e., it starts with a '/')
    // we can grab the last space-separated part of the line that starts with
    // a '/' and assume everything after it is the path to app.dill.
    return '/${appDillLine.split(' /').last}';
  }
}

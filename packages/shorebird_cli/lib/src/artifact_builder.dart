// cspell:words endtemplate aabs ipas appbundle bryanoltman codesign xcarchive
// cspell:words xcframework
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:stream_transform/stream_transform.dart';

/// Used to wrap code that invokes `flutter build` with Shorebird's fork of
/// Flutter.
typedef ShorebirdBuildCommand = Future<void> Function();

// FIXME: The following three apple BuildResult classes are identical and
// should be merged. They are all capturing the idea that we want to get the
// kernel (app.dill) file generated during a build so we can use it to link
// when patching.

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
  IosFrameworkBuildResult({
    required this.kernelFile,
  });

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

/// {@template artifact_build_exception}
/// Thrown when a build fails.
/// {@endtemplate}
class ArtifactBuildException implements Exception {
  /// {@macro artifact_build_exception}
  ArtifactBuildException(this.message);

  /// Information about the build failure.
  final String message;

  @override
  String toString() => message;
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

      final buildProcess = await process.start(
        executable,
        arguments,
        runInShell: true,
        environment: base64PublicKey?.toPublicKeyEnv(),
      );

      // Android builds are a series of gradle tasks that are all logged in
      // this format. We can use the 'Task :' line to get the current task
      // being run.
      final gradleTaskRegex = RegExp(r'^\[.*\] \> (Task :.*)$');
      buildProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (buildProgress == null) {
          return;
        }
        final captured = gradleTaskRegex.firstMatch(line)?.group(1);
        if (captured != null) {
          buildProgress.updateDetailMessage(captured);
        }
      });

      final stderrLines = await buildProcess.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      final stdErr = stderrLines.join('\n');
      final exitCode = await buildProcess.exitCode;
      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException('Failed to build: $stdErr');
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

      final result = await process.run(
        executable,
        arguments,
        runInShell: true,
        environment: base64PublicKey?.toPublicKeyEnv(),
      );

      if (result.exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          'Failed to build: ${result.stderr}',
        );
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

      final result = await process.run(
        executable,
        arguments,
        runInShell: true,
      );

      if (result.exitCode != ExitCode.success.code) {
        throw ArtifactBuildException('Failed to build: ${result.stderr}');
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

      final buildProcess = await process.start(
        executable,
        arguments,
        runInShell: true,
        environment: base64PublicKey?.toPublicKeyEnv(),
      );

      final stdoutLines = <String>[];
      buildProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stdoutLines.add(line);
        if (buildProgress == null) {
          return;
        }

        // TODO(bryanoltman): update the progress message for macOS builds.
        // final update = _progressUpdateFromMacosBuildLog(line);
        // if (update != null) {
        //   buildProgress.updateDetailMessage(update);
        // }
      });

      final stderrLines = await buildProcess.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      final stderr = stderrLines.join('\n');
      final stdout = stdoutLines.join('\n');
      final exitCode = await buildProcess.exitCode;
      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException('Failed to build: $stderr');
      }

      appDillPath = findAppDill(stdout: stdout);
    });

    if (appDillPath == null) {
      throw ArtifactBuildException('''
Unable to find app.dill file.
Please file a bug at https://github.com/shorebirdtech/shorebird/issues/new with the logs for this command.
''');
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

      final buildProcess = await process.start(
        executable,
        arguments,
        runInShell: true,
        environment: base64PublicKey?.toPublicKeyEnv(),
      );

      final stdoutLines = <String>[];
      buildProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stdoutLines.add(line);
        if (buildProgress == null) {
          return;
        }

        final update = _progressUpdateFromIpaBuildLog(line);
        if (update != null) {
          buildProgress.updateDetailMessage(update);
        }
      });

      final stderrLines = await buildProcess.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      final stderr = stderrLines.join('\n');
      final stdout = stdoutLines.join('\n');
      final exitCode = await buildProcess.exitCode;

      // If we've been updating the progress, reset it to the original base
      // message so as not to leave the user with a confusing message.
      buildProgress?.updateDetailMessage(null);

      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException('Failed to build: $stderr');
      }

      if (stderr.contains('Encountered error while creating the IPA')) {
        final errorMessage = _failedToCreateIpaErrorMessage(stderr: stderr);

        throw ArtifactBuildException('''
Failed to build:
$errorMessage''');
      }

      appDillPath = findAppDill(stdout: stdout);
    });

    if (appDillPath == null) {
      throw ArtifactBuildException('''
Unable to find app.dill file.
Please file a bug at https://github.com/shorebirdtech/shorebird/issues/new with the logs for this command.
''');
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

      final result = await process.run(
        executable,
        arguments,
        runInShell: true,
      );

      if (result.exitCode != ExitCode.success.code) {
        throw ArtifactBuildException('Failed to build: ${result.stderr}');
      }

      appDillPath = findAppDill(stdout: result.stdout.toString());
    });

    if (appDillPath == null) {
      throw ArtifactBuildException('''
Unable to find app.dill file.
Please file a bug at https://github.com/shorebirdtech/shorebird/issues/new with the logs for this command.
''');
    }

    return IosFrameworkBuildResult(kernelFile: File(appDillPath!));
  }

  String _failedToCreateIpaErrorMessage({required String stderr}) {
    // The full error text consists of many repeated lines of the format:
    // (newlines added for line length)
    //
    // [   +1 ms] Encountered error while creating the IPA:
    // [        ] error: exportArchive: Team "Team" does not have permission to
    //      create "iOS In House" provisioning profiles.
    //    error: exportArchive: No profiles for 'com.example.dev' were found
    //    error: exportArchive: No signing certificate "iOS Distribution" found
    //    error: exportArchive: Communication with Apple failed
    //    error: exportArchive: No signing certificate "iOS Distribution" found
    //    error: exportArchive: Team "My Team" does not have permission to
    //      create "iOS App Store" provisioning profiles.
    //    error: exportArchive: No profiles for 'com.example.demo' were found
    //    error: exportArchive: Communication with Apple failed
    //    error: exportArchive: No signing certificate "iOS Distribution" found
    //    error: exportArchive: Communication with Apple failed
    final exportArchiveRegex = RegExp(r'error: exportArchive:? (.+)$');
    return stderr
        .split('\n')
        .map((l) => l.trim())
        .toSet()
        .map(exportArchiveRegex.firstMatch)
        .whereType<Match>()
        .map((m) => '    ${m.group(1)!}')
        .join('\n');
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
      runInShell: true,
      useVendedFlutter: false,
    );

    if (result.exitCode != ExitCode.success.code) {
      logger.warn(
        '''
Build was successful, but `flutter pub get` failed to run after the build completed. You may see unexpected behavior in VS Code.

Either run `flutter pub get` manually, or follow the steps in ${cannotRunInVSCodeUrl.toLink()}.
''',
      );
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

    final result = await process.run(
      shorebirdArtifacts.getArtifactPath(artifact: genSnapshotArtifact),
      arguments,
    );

    if (result.exitCode != ExitCode.success.code) {
      throw ArtifactBuildException(
        'Failed to create snapshot: ${result.stderr}',
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
    print('entering build windows app');
    await _runShorebirdBuildCommand(() async {
      const executable = 'flutter';
      final arguments = [
        'build',
        'windows',
        '--release',
        if (flavor != null) '--flavor=$flavor',
        if (target != null) '--target=$target',
        ...args,
      ];

      print('starting build process');
      final buildProcess = await process.start(
        executable,
        arguments,
        runInShell: true,
        environment: base64PublicKey?.toPublicKeyEnv(),
      );

      buildProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        logger.detail(line);
        // TODO: update build progress
      });

      final stderrLines = await buildProcess.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      final stdErr = stderrLines.join('\n');
      print('awaiting exit code');
      final exitCode = await buildProcess.exitCode;
      print('exit code is $exitCode');
      if (exitCode != ExitCode.success.code) {
        throw ArtifactBuildException('Failed to build: $stdErr');
      }
    });

    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    // TODO: extract this to function, ensure this is correct
    return Directory(
      p.join(
        projectRoot.path,
        'build',
        'windows',
        'x64',
        'runner',
        'Release',
      ),
    );
  }

  /// Given a log of verbose output from `flutter build ipa`, returns a
  /// progress update message to display to the user if the line contains
  /// a known progress update step. Returns null (no update) otherwise.
  String? _progressUpdateFromIpaBuildLog(String line) {
    // xcodebuild -list is a command run early in `flutter build ipa` to read
    // build settings and schemes. Most users aren't familiar with this command,
    // so we translate it to "Collecting schemes" below.
    final collectingSchemesRegex =
        RegExp(r'\[.*\] executing:.*xcrun xcodebuild -list$');
    final archivingRegex = RegExp(r'^\[.*\] (Archiving .+$)');
    final runningXcodeBuildRegex = RegExp(r'^\[.*\] (Running Xcode build).*$');
    final compilingLinkingSigningRegex =
        RegExp(r'^\[.*\]\s+└─(Compiling, linking and signing).*$');
    final buildingAppStoreIpaRegex =
        RegExp(r'^\[.*\] (Building App Store IPA).*$');
    final builtAppStoreIpaRegex = RegExp(r'^\[.*\] ✓ (Built IPA to \S+).*$');

    final regexes = [
      archivingRegex,
      collectingSchemesRegex,
      runningXcodeBuildRegex,
      compilingLinkingSigningRegex,
      buildingAppStoreIpaRegex,
      builtAppStoreIpaRegex,
    ];

    for (final regex in regexes) {
      final match = regex.firstMatch(line);
      if (match == null) continue;

      // See the note above about the collectingSchemesRegex.
      if (regex == collectingSchemesRegex) {
        return 'Collecting schemes';
      }

      return match.group(1);
    }

    return null;
  }

  /// Given the full stdout from a `flutter build ipa` or `flutter build macos`
  /// command, finds the path to the app.dill file that was built.
  @visibleForTesting
  String? findAppDill({required String stdout}) {
    final appDillLine = stdout.split('\n').firstWhereOrNull(
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

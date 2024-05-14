import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// Used to wrap code that invokes `flutter build` with Shorebird's fork of
/// Flutter.
typedef ShorebirdBuildCommand = Future<void> Function();

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

      final result = await process.run(
        executable,
        arguments,
        runInShell: true,
      );

      if (result.exitCode != ExitCode.success.code) {
        throw ArtifactBuildException(
          'Failed to build: ${result.stderr}',
        );
      }
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

  Future<File> buildApk({
    String? flavor,
    String? target,
    Iterable<Arch>? targetPlatforms,
    bool splitPerAbi = false,
    List<String> args = const [],
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

  /// Calls `flutter build ipa`. If [codesign] is false, this will only build
  /// an .xcarchive and _not_ an .ipa.
  Future<void> buildIpa({
    bool codesign = true,
    File? exportOptionsPlist,
    String? flavor,
    String? target,
    List<String> args = const [],
  }) async {
    return _runShorebirdBuildCommand(() async {
      const executable = 'flutter';
      final exportOptionsPlistPath =
          (exportOptionsPlist ?? ios.createExportOptionsPlist()).path;
      final arguments = [
        'build',
        'ipa',
        '--release',
        if (flavor != null) '--flavor=$flavor',
        if (target != null) '--target=$target',
        if (!codesign) '--no-codesign',
        if (codesign) '''--export-options-plist=$exportOptionsPlistPath''',
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

      if (result.stderr
          .toString()
          .contains('Encountered error while creating the IPA')) {
        final errorMessage = _failedToCreateIpaErrorMessage(
          stderr: result.stderr.toString(),
        );

        throw ArtifactBuildException('''
Failed to build:
$errorMessage''');
      }
    });
  }

  /// Builds a release iOS framework (.xcframework) for the current project.
  Future<void> buildIosFramework({
    List<String> args = const [],
  }) {
    return _runShorebirdBuildCommand(() async {
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
    });
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
    final exportArchiveRegex = RegExp(r'error: exportArchive: (.+)$');

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

Either run `flutter pub get` manually, or follow the steps in ${link(uri: Uri.parse('https://docs.shorebird.dev/troubleshooting#i-installed-shorebird-and-now-i-cant-run-my-app-in-vs-code'))}.
''',
      );
    }
  }

  /// Creates an AOT snapshot of the given [appDillPath] at [outFilePath] and
  /// returns the resulting file.
  Future<File> buildElfAotSnapshot({
    required String appDillPath,
    required String outFilePath,
  }) async {
    final arguments = [
      '--deterministic',
      '--snapshot-kind=app-aot-elf',
      '--elf=$outFilePath',
      appDillPath,
    ];

    final result = await process.run(
      shorebirdArtifacts.getArtifactPath(
        artifact: ShorebirdArtifact.genSnapshot,
      ),
      arguments,
    );

    if (result.exitCode != ExitCode.success.code) {
      throw ArtifactBuildException(
        'Failed to create snapshot: ${result.stderr}',
      );
    }

    return File(outFilePath);
  }
}

import 'dart:io';

import 'package:io/io.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/platform/apple.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template ios_framework_releaser}
/// Functions to create an iOS framework release.
/// {@endtemplate}
class IosFrameworkReleaser extends Releaser {
  /// {@macro ios_framework_releaser}
  IosFrameworkReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  /// The directory where the release artifacts are stored.
  Directory get releaseDirectory => Directory(
    p.join(shorebirdEnv.getShorebirdProjectRoot()!.path, 'release'),
  );

  @override
  String get artifactDisplayName => 'iOS framework';

  @override
  ReleaseType get releaseType => ReleaseType.iosFramework;

  @override
  Future<void> assertArgsAreValid() async {
    if (!argResults.wasParsed('release-version')) {
      logger.err('Missing required argument: --release-version');
      throw ProcessExit(ExitCode.usage.code);
    }
  }

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        supportedOperatingSystems: {Platform.macOS},
        validators: doctor.iosCommandValidators,
      );
    } on PreconditionFailedException catch (e) {
      throw ProcessExit(e.exitCode.code);
    }

    final flutterVersionArg = argResults['flutter-version'] as String;
    if (flutterVersionArg != 'latest') {
      final version = await shorebirdFlutter.resolveFlutterVersion(
        flutterVersionArg,
      );
      if (version != null && version < minimumSupportedIosFlutterVersion) {
        logger.err('''
iOS releases are not supported with Flutter versions older than $minimumSupportedIosFlutterVersion.
For more information see: ${supportedFlutterVersionsUrl.toLink()}''');
        throw ProcessExit(ExitCode.usage.code);
      }
    }
  }

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    // Delete the Shorebird supplement directory if it exists.
    // This is to ensure that we don't accidentally upload stale artifacts
    // when building with older versions of Flutter.
    final shorebirdSupplementDir =
        artifactManager.getIosReleaseSupplementDirectory();
    if (shorebirdSupplementDir?.existsSync() ?? false) {
      shorebirdSupplementDir!.deleteSync(recursive: true);
    }

    await artifactBuilder.buildIosFramework(
      args: argResults.forwardedArgs,
      base64PublicKey: argResults.encodedPublicKey,
    );

    // Copy release xcframework to a new directory to avoid overwriting with
    // subsequent patch builds.
    final sourceLibraryDirectory = artifactManager.getAppXcframeworkDirectory();
    final targetLibraryDirectory = Directory(
      p.join(shorebirdEnv.getShorebirdProjectRoot()!.path, 'release'),
    );
    if (targetLibraryDirectory.existsSync()) {
      targetLibraryDirectory.deleteSync(recursive: true);
    }
    await copyPath(sourceLibraryDirectory.path, targetLibraryDirectory.path);

    // Rename Flutter.xcframework to ShorebirdFlutter.xcframework to avoid
    // Xcode warning users about the .xcframework signature changing.
    Directory(
      p.join(targetLibraryDirectory.path, 'Flutter.xcframework'),
    ).renameSync(
      p.join(targetLibraryDirectory.path, 'ShorebirdFlutter.xcframework'),
    );

    return targetLibraryDirectory;
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async {
    return argResults['release-version'] as String;
  }

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) {
    return codePushClientWrapper.createIosFrameworkReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      appFrameworkPath: p.join(releaseDirectory.path, 'App.xcframework'),
      supplementPath: artifactManager.getIosReleaseSupplementDirectory()?.path,
    );
  }

  @override
  Future<UpdateReleaseMetadata> updatedReleaseMetadata(
    UpdateReleaseMetadata metadata,
  ) async => metadata.copyWith(
    environment: metadata.environment.copyWith(
      xcodeVersion: await xcodeBuild.version(),
    ),
  );

  @override
  String get postReleaseInstructions {
    final relativeFrameworkDirectoryPath = p.relative(releaseDirectory.path);
    return '''

Your next step is to add the .xcframework files found in the ${lightCyan.wrap(relativeFrameworkDirectoryPath)} directory to your iOS app.

To do this:
    1. Add the relative path to the ${lightCyan.wrap(relativeFrameworkDirectoryPath)} directory to your app's Framework Search Paths in your Xcode build settings.
    2. Embed the App.xcframework and ShorebirdFlutter.framework in your Xcode project.

Instructions for these steps can be found at https://docs.flutter.dev/add-to-app/ios/project-setup#option-b---embed-frameworks-in-xcode.
''';
  }
}

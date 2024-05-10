import 'package:io/io.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version.dart';
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

  Directory get releaseDirectory => Directory(
        p.join(shorebirdEnv.getShorebirdProjectRoot()!.path, 'release'),
      );

  @override
  bool get requiresReleaseVersionArg => true;

  @override
  ReleaseType get releaseType => ReleaseType.iosFramework;

  @override
  Future<void> assertArgsAreValid() async {
    if (!argResults.wasParsed('release-version')) {
      logger.err('Missing required argument: --release-version');
      exit(ExitCode.usage.code);
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
      exit(e.exitCode.code);
    }
  }

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();

    final buildProgress = logger.progress(
      'Building iOS framework with Flutter $flutterVersionString',
    );

    try {
      await artifactBuilder.buildIosFramework(args: argResults.forwardedArgs);
    } catch (error) {
      buildProgress.fail('Failed to build iOS framework: $error');
      exit(ExitCode.software.code);
    }

    buildProgress.complete();

    // Copy release xcframework to a new directory to avoid overwriting with
    // subsequent patch builds.
    final sourceLibraryDirectory = artifactManager.getAppXcframeworkDirectory();
    final targetLibraryDirectory = Directory(
      p.join(shorebirdEnv.getShorebirdProjectRoot()!.path, 'release'),
    );
    if (targetLibraryDirectory.existsSync()) {
      targetLibraryDirectory.deleteSync(recursive: true);
    }
    await copyPath(
      sourceLibraryDirectory.path,
      targetLibraryDirectory.path,
    );

    // Rename Flutter.xcframework to ShorebirdFlutter.xcframework to avoid
    // Xcode warning users about the .xcframework signature changing.
    Directory(
      p.join(
        targetLibraryDirectory.path,
        'Flutter.xcframework',
      ),
    ).renameSync(
      p.join(
        targetLibraryDirectory.path,
        'ShorebirdFlutter.xcframework',
      ),
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
    );
  }

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

  @override
  Future<UpdateReleaseMetadata> releaseMetadata() async =>
      UpdateReleaseMetadata(
        releasePlatform: releaseType.releasePlatform,
        flutterVersionOverride: argResults['flutter-version'] as String?,
        generatedApks: false,
        environment: BuildEnvironmentMetadata(
          operatingSystem: platform.operatingSystem,
          operatingSystemVersion: platform.operatingSystemVersion,
          shorebirdVersion: packageVersion,
          xcodeVersion: await xcodeBuild.version(),
        ),
      );
}

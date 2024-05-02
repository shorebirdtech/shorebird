import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release_new/release_new_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template build_pipeline_exception}
/// An recoverable exception that occurs during the build pipeline. Will cause
/// the command to exit early with [exitCode] after logging [message] to the
/// console.
/// {@endtemplate}
class BuildPipelineException implements Exception {
  /// {@macro build_pipeline_exception}
  BuildPipelineException({
    required this.exitCode,
    required this.message,
  });

  /// The exit code to use when exiting the command.
  final ExitCode exitCode;

  /// The message to log to the console, if any.
  final String? message;

  @override
  String toString() =>
      'BuildPipelineException: $message (exit code: $exitCode)';
}

/// {@template release_pipeline}
/// A workflow to create a new release for a Shorebird app.
/// {@endtemplate}
abstract class ReleasePipeline {
  /// {@macro release_pipeline}
  ReleasePipeline({required this.argParser, required this.argResults});

  /// The [ArgParser] for the command. Used to find options we care about that
  /// were passed after a -- separator.
  final ArgParser argParser;

  /// The [ArgResults] for the command.
  final ArgResults argResults;

  /// Whether --release-version must be specified to patch. Currently only
  /// required for add-to-app/hybrid releases (aar and ios-framework).
  bool get requiresReleaseVersionArg => false;

  /// The type of artifact we are creating a release for.
  ReleaseType get releaseType;

  /// The shorebird app ID for the current project.
  String get appId => shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

  /// The root directory of the current project.
  Directory get projectRoot => shorebirdEnv.getShorebirdProjectRoot()!;

  /// The build flavor, if provided.
  late String? flavor = argResults.findOption('flavor', argParser: argParser);

  /// The target script, if provided.
  late String? target = argResults.findOption('target', argParser: argParser);

  /// The flutter version specified by the user, if any.
  late String? flutterVersionArg = argResults['flutter-version'] as String?;

  /// The workflow to create a new release for a Shorebird app.
  ///
  /// Expectations for methods invoked by this command:
  ///  - They perform their own logging. If an error occurs, they are
  ///    responsible for properly logging the error, cleaning up running
  ///    [Progress]es, etc.
  ///  - They can only exit early by throwing a [BuildPipelineException]. They
  ///    should otherwise return normally.
  Future<void> run() async {
    await validatePreconditions();
    await validateArgs();

    // This command handles logging, we don't need to provide our own
    // progress, error logs, etc.
    final app = await codePushClientWrapper.getApp(appId: appId);
    final targetFlutterVersion = await resolveTargetFlutterVersion();
    await shorebirdFlutter.installRevision(revision: targetFlutterVersion);

    final releaseFlutterShorebirdEnv = shorebirdEnv.copyWith(
      flutterRevisionOverride: targetFlutterVersion,
    );
    return await runScoped(
      () async {
        final releaseArtifact = await buildReleaseArtifacts();
        final releaseVersion =
            await getReleaseVersion(releaseArtifactRoot: releaseArtifact);

        // Ensure we can create a release from what we've built.
        await validateVersionIsReleasable(
          version: releaseVersion,
          flutterVersion: targetFlutterVersion,
        );

        // Ask the user to proceed (this is skipped when running via CI).
        await confirmCreateRelease(
          app: app,
          releaseVersion: releaseVersion,
          flutterVersion: targetFlutterVersion,
        );

        final release = await getOrCreateRelease(version: releaseVersion);
        await prepareRelease(release: release);
        await uploadReleaseArtifacts(release: release);
        await finalizeRelease(release: release);

        logger
          ..success('✅ Published Release ${release.version}!')
          ..info(postReleaseInstructions);

        printPatchInstructions(releaseVersion: releaseVersion);
      },
      values: {
        shorebirdEnvRef.overrideWith(() => releaseFlutterShorebirdEnv),
      },
    );
  }

  /// Asserts that the command can be run.
  Future<void> validatePreconditions();

  /// Asserts that the combination arguments passed to the command are valid.
  Future<void> validateArgs();

  /// Determines which Flutter version to use for the release. This will be
  /// either the version specified by the user or the version provided by
  /// [shorebirdEnv]. A [BuildPipelineException] will be thrown if the version
  /// specified by the user is not found/supported.
  Future<String> resolveTargetFlutterVersion() async {
    if (flutterVersionArg != null) {
      final String? revision;
      try {
        revision = await shorebirdFlutter.getRevisionForVersion(
          flutterVersionArg!,
        );
      } catch (error) {
        throw BuildPipelineException(
          message: '''
Unable to determine revision for Flutter version: $flutterVersionArg.
$error''',
          exitCode: ExitCode.software,
        );
      }

      if (revision == null) {
        final openIssueLink = link(
          uri: Uri.parse(
            'https://github.com/shorebirdtech/shorebird/issues/new?assignees=&labels=feature&projects=&template=feature_request.md&title=feat%3A+',
          ),
          message: 'open an issue',
        );
        throw BuildPipelineException(
          message: '''
Version $flutterVersionArg not found. Please $openIssueLink to request a new version.
Use `shorebird flutter versions list` to list available versions.
''',
          exitCode: ExitCode.software,
        );
      }

      return revision;
    }

    return shorebirdEnv.flutterRevision;
  }

  /// Builds the release artifacts for the given platform. Returns the "primary"
  /// artifact for the platform (e.g. the AAB for Android, the IPA for iOS).
  Future<FileSystemEntity> buildReleaseArtifacts();

  /// Extracts the release version from the compiled artifact.
  ///
  /// We extract the release version from the compiled artifact because we can
  /// be 100% certain that the artifact will report that same number when making
  /// patch check requests.
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  });

  /// Asserts that a release with version [version] can be released using
  /// flutter version [flutterVersion]. If a release has already been published
  /// with the given [version] for the platform associated with [releaseType],
  /// or if a release already exists with [version] but was compiled with a
  /// different Flutter revision, an error will be thrown.
  Future<void> validateVersionIsReleasable({
    required String version,
    required String flutterVersion,
  }) async {
    final existingRelease = await codePushClientWrapper.maybeGetRelease(
      appId: appId,
      releaseVersion: version,
    );

    if (existingRelease != null) {
      codePushClientWrapper.ensureReleaseIsNotActive(
        release: existingRelease,
        platform: releaseType.releasePlatform,
      );

      // All artifacts associated with a given release must be built
      // with the same Flutter revision.
      final errorMessage = '''
${styleBold.wrap(lightRed.wrap('A release with version $version already exists but was built using a different Flutter revision.'))}

  Existing release built with: ${lightCyan.wrap(existingRelease.flutterRevision)}
  Current release built with: ${lightCyan.wrap(flutterVersion)}

${styleBold.wrap(lightRed.wrap('All platforms for a given release must be built using the same Flutter revision.'))}

To resolve this issue, you can:
  * Re-run the release command with "${lightCyan.wrap('--flutter-version=${existingRelease.flutterRevision}')}".
  * Delete the existing release and re-run the release command with the desired Flutter version.
  * Bump the release version and re-run the release command with the desired Flutter version.''';
      throw BuildPipelineException(
        message: errorMessage,
        exitCode: ExitCode.software,
      );
    }
  }

  /// Prints a confirmation prompt with details about the release to be created.
  /// If the user confirms, the release will be created. If the user cancels,
  /// the command will exit with a success code. When running in a headless
  /// or CI environment, this prompt will print but will not wait for user
  /// confirmation.
  Future<void> confirmCreateRelease({
    required AppMetadata app,
    required String releaseVersion,
    required String flutterVersion,
  }) async {
    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();
    // TODO(bryanoltman): include archs in the summary for android
    // (and other platforms?)
    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.appId})')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '🕹️  Platform: ${lightCyan.wrap(releaseType.releasePlatform.name)}',
      '🐦 Flutter Version: ${lightCyan.wrap(flutterVersionString)}',
    ];

    logger.info('''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to create a new release!'))}

${summary.join('\n')}
''');

    if (shorebirdEnv.canAcceptUserInput) {
      final confirm = logger.confirm('Would you like to continue?');

      if (!confirm) {
        throw BuildPipelineException(
          message: 'Aborting.',
          exitCode: ExitCode.success,
        );
      }
    }
  }

  /// Fetches the release with version [version] from the server or creates a
  /// new release if none exists.
  Future<Release> getOrCreateRelease({required String version}) async {
    return await codePushClientWrapper.maybeGetRelease(
          appId: appId,
          releaseVersion: version,
        ) ??
        await codePushClientWrapper.createRelease(
          appId: appId,
          version: version,
          flutterRevision: shorebirdEnv.flutterRevision,
          platform: releaseType.releasePlatform,
        );
  }

  /// Prepares the release by updating the release status to draft.
  Future<void> prepareRelease({required Release release}) async {
    await codePushClientWrapper.updateReleaseStatus(
      appId: appId,
      releaseId: release.id,
      platform: releaseType.releasePlatform,
      status: ReleaseStatus.draft,
    );
  }

  /// Uploads the release artifacts to the CodePush server.
  Future<void> uploadReleaseArtifacts({required Release release});

  /// Metadata to attach to the release when creating it, used for debugging
  /// and support.
  UpdateReleaseMetadata get releaseMetadata;

  /// Finalizes the release by updating the release status to active.
  Future<void> finalizeRelease({required Release release}) async {
    await codePushClientWrapper.updateReleaseStatus(
      appId: appId,
      releaseId: release.id,
      platform: releaseType.releasePlatform,
      status: ReleaseStatus.active,
      metadata: releaseMetadata,
    );
  }

  /// Instructions explaining next steps after running `shorebird release`. This
  /// could include how to upload the generated artifact to a store and how to
  /// patch the release.
  String get postReleaseInstructions;

  /// Instructions explaining how to patch the release that was just creatd.
  void printPatchInstructions({
    required String releaseVersion,
    String? flavor,
    String? target,
  }) {
    final baseCommand = [
      'shorebird patch',
      '--platform=${releaseType.cliName}',
      if (flavor != null) '--flavor=$flavor',
      if (target != null) '--target=$target',
    ].join(' ');
    logger.info(
      '''To create a patch for this release, run ${lightCyan.wrap('$baseCommand --release-version=$releaseVersion')}''',
    );

    if (!requiresReleaseVersionArg) {
      logger.info(
        '''

Note: ${lightCyan.wrap(baseCommand)} without the --release-version option will patch the current version of the app.
''',
      );
    }
  }
}

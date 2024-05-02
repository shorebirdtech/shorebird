import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/command_pipeline/command_pipeline.dart';
import 'package:shorebird_cli/src/command_pipeline/steps/validate_android_args_step.dart';
import 'package:shorebird_cli/src/command_pipeline/steps/validate_android_preconditions_step.dart';
import 'package:shorebird_cli/src/commands/release_new/android_release_pipeline.dart';
import 'package:shorebird_cli/src/commands/release_new/release_pipeline_old.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// The different types of shorebird releases that can be created.
enum ReleaseType {
  /// An Android archive used in a hybrid app.
  aar,

  /// A full Flutter Android app.
  android,

  /// A full Flutter iOS app.
  ios,

  /// An iOS framework used in a hybrid app.
  iosFramework;

  /// The CLI argument used to specify the release type(s).
  String get cliName {
    switch (this) {
      case ReleaseType.android:
        return 'android';
      case ReleaseType.ios:
        return 'ios';
      case ReleaseType.iosFramework:
        return 'ios-framework';
      case ReleaseType.aar:
        return 'aar';
    }
  }

  /// The platform associated with the release type.
  ReleasePlatform get releasePlatform {
    switch (this) {
      case ReleaseType.aar:
        return ReleasePlatform.android;
      case ReleaseType.android:
        return ReleasePlatform.android;
      case ReleaseType.ios:
        return ReleasePlatform.ios;
      case ReleaseType.iosFramework:
        return ReleasePlatform.ios;
    }
  }

  /// Whether --release-version must be specified to patch.
  bool requiresReleaseVersionArg() {
    switch (this) {
      case ReleaseType.aar:
        return true;
      case ReleaseType.android:
        return false;
      case ReleaseType.ios:
        return false;
      case ReleaseType.iosFramework:
        return true;
    }
  }
}

/// {@template release_command}
/// Creates a new app release for the specified platform(s).
/// {@endtemplate}
class ReleaseNewCommand extends ShorebirdCommand {
  /// {@macro release_command}
  ReleaseNewCommand() {
    argParser
      ..addOption(
        'target',
        abbr: 't',
        help: 'The main entrypoint file of the application.',
      )
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      )
      ..addOption(
        'flutter-version',
        help: 'The Flutter version to use when building the app (e.g: 3.16.3).',
      )
      ..addOption(
        'android-artifact',
        help:
            '''The type of artifact to generate. Only relevant for Android releases.''',
        allowed: ['aab', 'apk'],
        defaultsTo: 'aab',
        allowedHelp: {
          'aab': 'Android App Bundle',
          'apk': 'Android Package Kit',
        },
      )
      ..addMultiOption(
        'platform',
        abbr: 'p',
        help: 'The platform(s) to to build this release for.',
        allowed: ReleaseType.values.map((e) => e.cliName).toList(),
        // TODO(bryanoltman): uncomment this once https://github.com/dart-lang/args/pull/273 lands
        // mandatory: true.
      )
      ..addOption(
        'release-version',
        help: '''
The version of the associated release (e.g. "1.0.0"). This should be the version
of the iOS app that is using this module.''',
      )
      ..addMultiOption(
        'android-target-platform',
        help: 'The target platform(s) for which the app is compiled.',
        defaultsTo: Arch.values.map((arch) => arch.targetPlatformCliArg),
        allowed: Arch.values.map((arch) => arch.targetPlatformCliArg),
      );
  }

  @override
  String get description =>
      'Creates a shorebird release for the provided target platforms';

  @override
  String get name => 'release-new';

  // Creating a release consists of the following steps:
  // 1. Verify preconditions
  // 2. Install the target flutter version if necessary
  // 3. Build the app for each target platform
  // 4. Extract the release version from the compiled artifact OR use the
  //    release version provided.
  // 5. Verify the release does not conflict with an existing release.
  // 6. Create a new release in the database.
  @override
  Future<int> run() async {
    try {
      await Future.wait(pipelines.map((p) => p.run()));
    } on BuildPipelineException catch (e) {
      logger.err(e.message);
      return e.exitCode.code;
    }

    return ExitCode.success.code;
  }

  @visibleForTesting
  Iterable<CommandPipeline> get pipelines =>
      (results['platform'] as List<String>)
          .map(
            (platformArg) => ReleaseType.values.firstWhere(
              (target) => target.cliName == platformArg,
            ),
          )
          .map(_getPipeline);

  CommandPipeline _getPipeline(ReleaseType releaseType) {
    switch (releaseType) {
      case ReleaseType.android:
        return CommandPipeline(
          steps: [
            ValidateAndroidArgsStep(),
            ValidateAndroidPreconditionsStep(),
          ],
        );
      case ReleaseType.ios:
        throw UnimplementedError();
      // return IosReleasePipeline(argResults: argResults);
      case ReleaseType.iosFramework:
        throw UnimplementedError();
      // return IosFrameworkReleasePipeline(argResults: argResults);
      case ReleaseType.aar:
        throw UnimplementedError();
      // return AarReleasePipeline(argResults: argResults);
    }
  }

  ReleasePipelineOld _getPipelineOld(ReleaseType releaseType) {
    switch (releaseType) {
      case ReleaseType.android:
        return AndroidReleasePipline(
          argResults: results,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.ios:
        throw UnimplementedError();
      // return IosReleasePipeline(argResults: argResults);
      case ReleaseType.iosFramework:
        throw UnimplementedError();
      // return IosFrameworkReleasePipeline(argResults: argResults);
      case ReleaseType.aar:
        throw UnimplementedError();
      // return AarReleasePipeline(argResults: argResults);
    }
  }

  /// Whether --release-version must be specified to patch. Currently only
  /// required for add-to-app/hybrid releases (aar and ios-framework).
  bool get requiresReleaseVersionArg => false;

  /// The shorebird app ID for the current project.
  String get appId => shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

  /// The root directory of the current project.
  Directory get projectRoot => shorebirdEnv.getShorebirdProjectRoot()!;

  /// The build flavor, if provided.
  late String? flavor = results.findOption('flavor', argParser: argParser);

  /// The target script, if provided.
  late String? target = results.findOption('target', argParser: argParser);

  /// The flutter version specified by the user, if any.
  late String? flutterVersionArg = results['flutter-version'] as String?;

  /// The workflow to create a new release for a Shorebird app.
  ///
  /// Expectations for methods invoked by this command:
  ///  - They perform their own logging. If an error occurs, they are
  ///    responsible for properly logging the error, cleaning up running
  ///    [Progress]es, etc.
  ///  - They can only exit early by throwing a [BuildPipelineException]. They
  ///    should otherwise return normally.
  Future<void> createRelease(ReleasePipelineOld pipeline) async {
    await pipeline.validatePreconditions();
    await pipeline.validateArgs();

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
        final releaseArtifact = await pipeline.buildReleaseArtifacts();
        final releaseVersion = await pipeline.getReleaseVersion(
          releaseArtifactRoot: releaseArtifact,
        );

        // Ensure we can create a release from what we've built.
        await validateVersionIsReleasable(
          version: releaseVersion,
          flutterVersion: targetFlutterVersion,
          releasePlatform: pipeline.releaseType.releasePlatform,
        );

        // Ask the user to proceed (this is skipped when running via CI).
        await confirmCreateRelease(
          app: app,
          releaseVersion: releaseVersion,
          flutterVersion: targetFlutterVersion,
          releasePlatform: pipeline.releaseType.releasePlatform,
        );

        final release = await getOrCreateRelease(
          version: releaseVersion,
          releasePlatform: pipeline.releaseType.releasePlatform,
        );
        await prepareRelease(release: release, pipeline: pipeline);
        await pipeline.uploadReleaseArtifacts(release: release, appId: appId);
        await finalizeRelease(release: release, pipeline: pipeline);

        logger
          ..success('✅ Published Release ${release.version}!')
          ..info(pipeline.postReleaseInstructions);

        printPatchInstructions(
          releaseVersion: releaseVersion,
          releaseType: pipeline.releaseType,
        );
      },
      values: {
        shorebirdEnvRef.overrideWith(() => releaseFlutterShorebirdEnv),
      },
    );
  }

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

  /// Asserts that a release with version [version] can be released using
  /// flutter version [flutterVersion]. If a release has already been published
  /// with the given [version] for the platform [releasePlatform], or if a
  /// release already exists with [version] but was compiled with a different
  /// Flutter revision, an error will be thrown.
  Future<void> validateVersionIsReleasable({
    required String version,
    required String flutterVersion,
    required ReleasePlatform releasePlatform,
  }) async {
    final existingRelease = await codePushClientWrapper.maybeGetRelease(
      appId: appId,
      releaseVersion: version,
    );

    if (existingRelease != null) {
      codePushClientWrapper.ensureReleaseIsNotActive(
        release: existingRelease,
        platform: releasePlatform,
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
    required ReleasePlatform releasePlatform,
  }) async {
    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();
    // TODO(bryanoltman): include archs in the summary for android
    // (and other platforms?)
    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.appId})')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '🕹️  Platform: ${lightCyan.wrap(releasePlatform.name)}',
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
  Future<Release> getOrCreateRelease({
    required String version,
    required ReleasePlatform releasePlatform,
  }) async {
    return await codePushClientWrapper.maybeGetRelease(
          appId: appId,
          releaseVersion: version,
        ) ??
        await codePushClientWrapper.createRelease(
          appId: appId,
          version: version,
          flutterRevision: shorebirdEnv.flutterRevision,
          platform: releasePlatform,
        );
  }

  /// Prepares the release by updating the release status to draft.
  Future<void> prepareRelease({
    required Release release,
    required ReleasePipelineOld pipeline,
  }) async {
    await codePushClientWrapper.updateReleaseStatus(
      appId: appId,
      releaseId: release.id,
      platform: pipeline.releaseType.releasePlatform,
      status: ReleaseStatus.draft,
    );
  }

  /// Finalizes the release by updating the release status to active.
  Future<void> finalizeRelease({
    required Release release,
    required ReleasePipelineOld pipeline,
  }) async {
    await codePushClientWrapper.updateReleaseStatus(
      appId: appId,
      releaseId: release.id,
      platform: pipeline.releaseType.releasePlatform,
      status: ReleaseStatus.active,
      metadata: pipeline.releaseMetadata,
    );
  }

  /// Instructions explaining how to patch the release that was just creatd.
  void printPatchInstructions({
    required String releaseVersion,
    required ReleaseType releaseType,
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

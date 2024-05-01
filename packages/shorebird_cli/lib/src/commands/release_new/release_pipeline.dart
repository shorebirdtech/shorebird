import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release_new/release_new_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

abstract class ReleasePipeline {
  ReleasePipeline({required this.argParser, required this.argResults});

  final ArgParser argParser;
  final ArgResults argResults;

  /// Whether --release-version must be specified to patch. Currently only
  /// required for add-to-app/hybrid releases (aar and ios-framework).
  bool get requiresReleaseVersionArg => false;

  ReleasePlatform get releasePlatform;
  ReleaseTarget get releaseTarget;

  String get appId => shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);
  Directory get projectRoot => shorebirdEnv.getShorebirdProjectRoot()!;

  late String? flavor = argResults.findOption('flavor', argParser: argParser);
  late String? target = argResults.findOption('target', argParser: argParser);
  late String? flutterVersionArg = argResults['flutter-version'] as String?;

  Future<void> run() async {
    await validatePreconditions();
    await validateArgs();

    final fetchAppProgress = logger.progress('Fetching app data');
    final app = await codePushClientWrapper.getApp(appId: appId);
    fetchAppProgress.complete();

    final targetFlutterVersion = await resolveTargetFlutterVersion();
    await installFlutterRevisionIfNeeded(revision: targetFlutterVersion);
    final releaseFlutterShorebirdEnv = shorebirdEnv.copyWith(
      flutterRevisionOverride: targetFlutterVersion,
    );
    return await runScoped(
      () async {
        final buildProgress = logger.progress('Building release artifacts');
        final releaseArtifact = await buildReleaseArtifacts();
        buildProgress.complete();

        final releaseVersionProgress =
            logger.progress('Determining release version');
        final releaseVersion =
            await getReleaseVersion(releaseArtifactRoot: releaseArtifact);
        releaseVersionProgress.complete();

        await validateVersionIsReleasable(
          version: releaseVersion,
          flutterVersion: targetFlutterVersion,
        );

        confirmRelease(
          app: app,
          releaseVersion: releaseVersion,
          flutterVersion: targetFlutterVersion,
        );

        final release = await getOrCreateRelease(version: releaseVersion);
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

  Future<void> uploadReleaseArtifacts({required Release release});

  Future<String> resolveTargetFlutterVersion() async {
    if (flutterVersionArg != null) {
      final String? revision;
      try {
        revision = await shorebirdFlutter.getRevisionForVersion(
          flutterVersionArg!,
        );
      } catch (error) {
        logger.err(
          '''
Unable to determine revision for Flutter version: $flutterVersion.
$error''',
        );
        throw ExitCode.software.code;
      }

      if (revision == null) {
        final openIssueLink = link(
          uri: Uri.parse(
            'https://github.com/shorebirdtech/shorebird/issues/new?assignees=&labels=feature&projects=&template=feature_request.md&title=feat%3A+',
          ),
          message: 'open an issue',
        );
        logger.err('''
Version $flutterVersion not found. Please $openIssueLink to request a new version.
Use `shorebird flutter versions list` to list available versions.
''');
        throw ExitCode.software.code;
      }

      return revision;
    }

    return shorebirdEnv.flutterRevision;
  }

  Future<String> flutterVersion({String? releaseVersion}) async {
    if (releaseVersion == null) {
      return shorebirdEnv.flutterRevision;
    }

    final release = await codePushClientWrapper.getRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );

    if (flutterVersionArg != null &&
        release.flutterRevision != flutterVersionArg) {
      _printConflictingFlutterRevisionError(
        existingFlutterRevision: release.flutterRevision,
        currentFlutterRevision: flutterVersionArg!,
        releaseVersion: releaseVersion,
      );
      throw ExitCode.software.code;
    }

    return release.flutterRevision;
  }

  Future<void> validateArgs();

  Future<void> validatePreconditions();

  Future<void> installFlutterRevisionIfNeeded({
    required String revision,
  }) async {
    try {
      await shorebirdFlutter.installRevision(
        revision: revision,
      );
    } catch (_) {
      throw ExitCode.software.code;
    }
  }

  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  });

  // Check if the version is already released
  // Check if the version is already released with a different flutter version
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
        platform: releasePlatform,
      );

      // All artifacts associated with a given release must be built
      // with the same Flutter revision.
      if (existingRelease.flutterRevision != flutterVersion) {
        _printConflictingFlutterRevisionError(
          existingFlutterRevision: existingRelease.flutterRevision,
          currentFlutterRevision: flutterVersion,
          releaseVersion: version,
        );
        throw ExitCode.software.code;
      }
    }
  }

  Future<Release> getOrCreateRelease({required String version}) async {
    final existingRelease = await codePushClientWrapper.maybeGetRelease(
      appId: appId,
      releaseVersion: version,
    );

    if (existingRelease != null) {
      codePushClientWrapper.ensureReleaseIsNotActive(
        release: existingRelease,
        platform: releasePlatform,
      );
    }

    final Release release;
    if (existingRelease != null) {
      release = existingRelease;
      await codePushClientWrapper.updateReleaseStatus(
        appId: appId,
        releaseId: release.id,
        platform: releasePlatform,
        status: ReleaseStatus.draft,
      );
    } else {
      release = await codePushClientWrapper.createRelease(
        appId: appId,
        version: version,
        flutterRevision: shorebirdEnv.flutterRevision,
        platform: releasePlatform,
      );
    }

    return release;
  }

  Future<void> finalizeRelease({required Release release}) async {
    await codePushClientWrapper.updateReleaseStatus(
      appId: appId,
      releaseId: release.id,
      platform: releasePlatform,
      status: ReleaseStatus.active,
      metadata: UpdateReleaseMetadata(
        releasePlatform: releasePlatform,
        flutterVersionOverride: flutterVersionArg,
        generatedApks: false, // TODO
        environment: BuildEnvironmentMetadata(
          operatingSystem: platform.operatingSystem,
          operatingSystemVersion: platform.operatingSystemVersion,
          shorebirdVersion: packageVersion,
          xcodeVersion: null,
        ),
      ),
    );
  }

  /// Instructions explaining next steps after running `shorebird release`. This
  /// could include how to upload the generated artifact to a store and how to
  /// patch the release.
  String get postReleaseInstructions;

  /// Builds the release artifacts for the given platform. Returns the "primary"
  /// artifact for the platform (e.g. the AAB for Android, the IPA for iOS).
  Future<FileSystemEntity> buildReleaseArtifacts();

  void confirmRelease({
    required AppMetadata app,
    required String releaseVersion,
    required String flutterVersion,
  }) {
    // TODO(bryanoltman): include archs in the summary for android (and other platforms?)
    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.appId})')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '🕹️  Platform: ${lightCyan.wrap(releasePlatform.name)}',
      '🐦 Flutter Version: ${lightCyan.wrap(flutterVersion)}',
    ];

    logger.info('''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to create a new release!'))}

${summary.join('\n')}
''');

    if (shorebirdEnv.canAcceptUserInput) {
      final confirm = logger.confirm('Would you like to continue?');

      if (!confirm) {
        logger.info('Aborting.');
        throw ExitCode.success.code;
      }
    }
  }

  void printPatchInstructions({
    required String releaseVersion,
    String? flavor,
    String? target,
  }) {
    final baseCommand = [
      'shorebird patch',
      releaseTarget.cliName,
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

  static void _printConflictingFlutterRevisionError({
    required String existingFlutterRevision,
    required String currentFlutterRevision,
    required String releaseVersion,
  }) {
    logger.err(
      '''
${styleBold.wrap(lightRed.wrap('A release with version $releaseVersion already exists but was built using a different Flutter revision.'))}

  Existing release built with: ${lightCyan.wrap(existingFlutterRevision)}
  Current release built with: ${lightCyan.wrap(currentFlutterRevision)}

${styleBold.wrap(lightRed.wrap('All platforms for a given release must be built using the same Flutter revision.'))}

To resolve this issue, you can:
  * Re-run the release command with "${lightCyan.wrap('--flutter-version=$existingFlutterRevision')}".
  * Delete the existing release and re-run the release command with the desired Flutter version.
  * Bump the release version and re-run the release command with the desired Flutter version.''',
    );
  }
}

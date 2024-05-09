import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/release/release.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

typedef ResolveReleaser = Releaser Function(ReleaseType releaseType);

/// {@template release_command}
/// Creates a new app release for the specified platform(s).
/// {@endtemplate}
class ReleaseCommand extends ShorebirdCommand {
  /// {@macro release_command}
  ReleaseCommand({ResolveReleaser? resolveReleaser}) {
    _resolveReleaser = resolveReleaser ?? getReleaser;
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
        'build-number',
        help: '''
An identifier used as an internal version number.
Each build must have a unique identifier to differentiate it from previous builds.
It is used to determine whether one build is more recent than another, with higher numbers indicating more recent build.
On Android it is used as "versionCode".
On Xcode builds it is used as "CFBundleVersion".''',
        defaultsTo: '1.0',
      )
      ..addFlag(
        'codesign',
        help: 'Codesign the application bundle (iOS only).',
        defaultsTo: true,
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Validate but do not upload the release.',
      )
      ..addOption(
        exportOptionsPlistArgName,
        help:
            '''Export an IPA with these options. See "xcodebuild -h" for available exportOptionsPlist keys (iOS only).''',
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
        'platforms',
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
        'target-platform',
        help: 'The target platform(s) for which the app is compiled.',
        defaultsTo: Arch.values.map((arch) => arch.targetPlatformCliArg),
        allowed: Arch.values.map((arch) => arch.targetPlatformCliArg),
      );
  }

  late final ResolveReleaser _resolveReleaser;

  @override
  String get description =>
      'Creates a shorebird release for the provided target platforms';

  @override
  String get name => 'release';

  @override
  Future<int> run() async {
    final releaserFutures =
        results.releaseTypes.map(_resolveReleaser).map(createRelease);

    for (final future in releaserFutures) {
      await future;
    }

    return ExitCode.success.code;
  }

  @visibleForTesting
  Releaser getReleaser(ReleaseType releaseType) {
    switch (releaseType) {
      case ReleaseType.android:
        return AndroidReleaser(
          argResults: results,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.ios:
        return IosReleaser(
          argResults: results,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.iosFramework:
        return IosFrameworkReleaser(
          argResults: results,
          flavor: flavor,
          target: target,
        );
      case ReleaseType.aar:
        return AarReleaser(
          argResults: results,
          flavor: flavor,
          target: target,
        );
    }
  }

  /// The shorebird app ID for the current project.
  String get appId => shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

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
  ///  - They handle their own exceptions and exit with a non-zero exit code if
  ///    an error occurs *instead of* throwing an exception.
  @visibleForTesting
  Future<void> createRelease(Releaser releaser) async {
    await releaser.assertPreconditions();
    await releaser.assertArgsAreValid();

    await cache.updateAll();

    // This command handles logging, we don't need to provide our own
    // progress, error logs, etc.
    final app = await codePushClientWrapper.getApp(appId: appId);
    final targetFlutterRevision = await resolveTargetFlutterRevision();
    try {
      await shorebirdFlutter.installRevision(revision: targetFlutterRevision);
    } catch (_) {
      exit(ExitCode.software.code);
    }

    final releaseFlutterShorebirdEnv = shorebirdEnv.copyWith(
      flutterRevisionOverride: targetFlutterRevision,
    );
    return await runScoped(
      () async {
        await cache.updateAll();

        final releaseArtifact = await releaser.buildReleaseArtifacts();
        final releaseVersion = await releaser.getReleaseVersion(
          releaseArtifactRoot: releaseArtifact,
        );

        // Ensure we can create a release from what we've built.
        await ensureVersionIsReleasable(
          version: releaseVersion,
          flutterRevision: targetFlutterRevision,
          releasePlatform: releaser.releaseType.releasePlatform,
        );

        final dryRun = results['dry-run'] == true;
        if (dryRun) {
          logger
            ..info('No issues detected.')
            ..info('The server may enforce additional checks.');
          exit(ExitCode.success.code);
        }

        // Ask the user to proceed (this is skipped when running via CI).
        await confirmCreateRelease(
          app: app,
          releaseVersion: releaseVersion,
          flutterVersion: targetFlutterRevision,
          releasePlatform: releaser.releaseType.releasePlatform,
        );

        final release = await getOrCreateRelease(
          version: releaseVersion,
          releasePlatform: releaser.releaseType.releasePlatform,
        );
        await prepareRelease(release: release, releaser: releaser);
        await releaser.uploadReleaseArtifacts(release: release, appId: appId);
        await finalizeRelease(release: release, releaser: releaser);

        logger
          ..success('''

✅ Published Release ${release.version}!''')
          ..info(releaser.postReleaseInstructions);

        printPatchInstructions(
          releaser: releaser,
          releaseVersion: releaseVersion,
          releaseType: releaser.releaseType,
          flavor: flavor,
          target: target,
        );
      },
      values: {
        shorebirdEnvRef.overrideWith(() => releaseFlutterShorebirdEnv),
      },
    );
  }

  /// Determines which Flutter version to use for the release. This will be
  /// either the version specified by the user or the version provided by
  /// [shorebirdEnv]. Will exit with [ExitCode.software] if the version
  /// specified by the user is not found/supported.
  Future<String> resolveTargetFlutterRevision() async {
    if (flutterVersionArg != null) {
      final String? revision;
      try {
        revision = await shorebirdFlutter.getRevisionForVersion(
          flutterVersionArg!,
        );
      } catch (error) {
        logger.err(
          '''
Unable to determine revision for Flutter version: $flutterVersionArg.
$error''',
        );
        exit(ExitCode.software.code);
      }

      if (revision == null) {
        final openIssueLink = link(
          uri: Uri.parse(
            'https://github.com/shorebirdtech/shorebird/issues/new?assignees=&labels=feature&projects=&template=feature_request.md&title=feat%3A+',
          ),
          message: 'open an issue',
        );
        logger.err(
          '''
Version $flutterVersionArg not found. Please $openIssueLink to request a new version.
Use `shorebird flutter versions list` to list available versions.
''',
        );
        exit(ExitCode.software.code);
      }

      return revision;
    }

    return shorebirdEnv.flutterRevision;
  }

  /// Asserts that a release with version [version] can be released using
  /// flutter revision [flutterRevision]. If a release has already been
  /// published with the given [version] for the platform [releasePlatform], or
  /// if a release already exists with [version] but was compiled with a
  /// different Flutter revision, an error will be thrown.
  Future<void> ensureVersionIsReleasable({
    required String version,
    required String flutterRevision,
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
      if (existingRelease.flutterRevision != flutterRevision) {
        logger
          ..err('''
${styleBold.wrap(lightRed.wrap('A release with version $version already exists but was built using a different Flutter revision.'))}
''')
          ..info('''

  Existing release built with: ${lightCyan.wrap(existingRelease.flutterRevision)}
  Current release built with: ${lightCyan.wrap(flutterRevision)}

${styleBold.wrap(lightRed.wrap('All platforms for a given release must be built using the same Flutter revision.'))}

To resolve this issue, you can:
  * Re-run the release command with "${lightCyan.wrap('--flutter-version=${existingRelease.flutterRevision}')}".
  * Delete the existing release and re-run the release command with the desired Flutter version.
  * Bump the release version and re-run the release command with the desired Flutter version.''');
        exit(ExitCode.software.code);
      }
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
        logger.info('Aborting.');
        exit(ExitCode.success.code);
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
    required Releaser releaser,
  }) async {
    await codePushClientWrapper.updateReleaseStatus(
      appId: appId,
      releaseId: release.id,
      platform: releaser.releaseType.releasePlatform,
      status: ReleaseStatus.draft,
    );
  }

  /// Finalizes the release by updating the status to active.
  Future<void> finalizeRelease({
    required Release release,
    required Releaser releaser,
  }) async {
    await codePushClientWrapper.updateReleaseStatus(
      appId: appId,
      releaseId: release.id,
      platform: releaser.releaseType.releasePlatform,
      status: ReleaseStatus.active,
      metadata: await releaser.releaseMetadata(),
    );
  }

  /// Instructions explaining how to patch the release that was just creatd.
  void printPatchInstructions({
    required Releaser releaser,
    required String releaseVersion,
    required ReleaseType releaseType,
    String? flavor,
    String? target,
  }) {
    final baseCommand = [
      'shorebird patch',
      '--platforms=${releaseType.cliName}',
      if (flavor != null) '--flavor=$flavor',
      if (target != null) '--target=$target',
    ].join(' ');
    logger.info(
      '''To create a patch for this release, run ${lightCyan.wrap('$baseCommand --release-version=$releaseVersion')}''',
    );

    if (!releaser.requiresReleaseVersionArg) {
      logger.info(
        '''

Note: ${lightCyan.wrap(baseCommand)} without the --release-version option will patch the current version of the app.
''',
      );
    }
  }
}

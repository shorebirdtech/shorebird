import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/formatters/file_size_formatter.dart';
import 'package:shorebird_cli/src/ios.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

class PatchIosFrameworkCommand extends ShorebirdCommand
    with
        ShorebirdConfigMixin,
        ShorebirdValidationMixin,
        ShorebirdBuildMixin,
        ShorebirdArtifactMixin {
  PatchIosFrameworkCommand({
    HashFunction? hashFn,
  }) : _hashFn = hashFn ?? ((m) => sha256.convert(m).toString()) {
    argParser
      ..addOption(
        'release-version',
        help: '''
The version of the associated release (e.g. "1.0.0"). This should be the version
of the iOS app that is using this module.''',
        mandatory: true,
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Patch without confirmation if there are no errors.',
        negatable: false,
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Validate but do not upload the patch.',
      );
  }

  final HashFunction _hashFn;

  @override
  String get name => 'ios-framework-alpha';

  @override
  String get description =>
      'Publish new patches for a specific iOS framework release to Shorebird.';

  @override
  Future<int> run() async {
    if (!platform.isMacOS) {
      logger.err('This command is only supported on macOS.');
      return ExitCode.unavailable.code;
    }

    try {
      await validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.iosCommandValidators,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    showiOSStatusWarning();

    const arch = 'aarch64';
    const channelName = 'stable';
    const releasePlatform = ReleasePlatform.ios;
    final releaseVersion = results['release-version'] as String;
    final dryRun = results['dry-run'] == true;
    final shorebirdYaml = ShorebirdEnvironment.getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId();
    final app = await codePushClientWrapper.getApp(appId: appId);

    final release = await codePushClientWrapper.getRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );

    if (release.platformStatuses[ReleasePlatform.ios] == ReleaseStatus.draft) {
      logger.err('''
Release $releaseVersion is in an incomplete state. It's possible that the original release was terminated or failed to complete.

Please re-run the release command for this version or create a new release.''');
      return ExitCode.software.code;
    }

    final buildProgress = logger.progress('Building patch');
    try {
      await buildIosFramework();
      buildProgress.complete();
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    final File aotFile;
    try {
      final newestDillFile = newestAppDill();
      aotFile = await buildElfAotSnapshot(appDillPath: newestDillFile.path);
    } catch (error) {
      buildProgress.fail('$error');
      return ExitCode.software.code;
    }

    buildProgress.complete();

    final flutterRevisionProgress = logger.progress(
      'Fetching Flutter revision',
    );
    final String shorebirdFlutterRevision;
    try {
      shorebirdFlutterRevision = await getShorebirdFlutterRevision();
      flutterRevisionProgress.complete();
    } catch (error) {
      flutterRevisionProgress.fail('$error');
      return ExitCode.software.code;
    }

    if (release.flutterRevision != shorebirdFlutterRevision) {
      logger
        ..err('''
Flutter revision mismatch.

The release you are trying to patch was built with a different version of Flutter.

Release Flutter Revision: ${release.flutterRevision}
Current Flutter Revision: $shorebirdFlutterRevision
''')
        ..info(
          '''
Either create a new release using:
  ${lightCyan.wrap('shorebird release')}

Or downgrade your Flutter version and try again using:
  ${lightCyan.wrap('cd ${ShorebirdEnvironment.flutterDirectory.path}')}
  ${lightCyan.wrap('git checkout ${release.flutterRevision}')}

Shorebird plans to support this automatically, let us know if it's important to you:
https://github.com/shorebirdtech/shorebird/issues/472
''',
        );
      return ExitCode.software.code;
    }

    if (dryRun) {
      logger
        ..info('No issues detected.')
        ..info('The server may enforce additional checks.');
      return ExitCode.success.code;
    }

    final aotFileSize = aotFile.statSync().size;

    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('($appId)')}''',
      // TODO(felangel): uncomment once flavor support is added.
      // if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '📺 Channel: ${lightCyan.wrap(channelName)}',
      '''🕹️  Platform: ${lightCyan.wrap(releasePlatform.name)} ${lightCyan.wrap('[$arch (${formatBytes(aotFileSize)})]')}''',
    ];

    logger.info(
      '''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to publish a new patch!'))}

${summary.join('\n')}
''',
    );

    // TODO(bryanoltman): check for asset changes
    final force = results['force'] == true;
    final needsConfirmation = !force;
    if (needsConfirmation) {
      final confirm = logger.confirm('Would you like to continue?');

      if (!confirm) {
        logger.info('Aborting.');
        return ExitCode.success.code;
      }
    }

    await codePushClientWrapper.publishPatch(
      appId: appId,
      releaseId: release.id,
      platform: releasePlatform,
      channelName: channelName,
      patchArtifactBundles: {
        Arch.arm64: PatchArtifactBundle(
          arch: arch,
          path: aotFile.path,
          hash: _hashFn(aotFile.readAsBytesSync()),
          size: aotFileSize,
        ),
      },
    );

    logger.success('\n✅ Published Patch!');
    return ExitCode.success.code;
  }
}

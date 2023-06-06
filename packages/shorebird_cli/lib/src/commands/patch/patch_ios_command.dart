import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/formatters/file_size_formatter.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_code_push_client_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template patch_ios_command}
/// `shorebird patch ios-preview` command.
/// {@endtemplate}
class PatchIosCommand extends ShorebirdCommand
    with
        ShorebirdConfigMixin,
        ShorebirdBuildMixin,
        ShorebirdValidationMixin,
        ShorebirdArtifactMixin,
        ShorebirdCodePushClientMixin {
  /// {@macro patch_ios_command}
  PatchIosCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
    super.validators,
    HashFunction? hashFn,
    IpaReader? ipaReader,
  })  : _hashFn = hashFn ?? ((m) => sha256.convert(m).toString()),
        _ipaReader = ipaReader ?? IpaReader() {
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

  @override
  String get name => 'ios-preview';

  @override
  String get description =>
      'Publish new patches for a specific iOS release to Shorebird.';

  final HashFunction _hashFn;
  final IpaReader _ipaReader;

  @override
  Future<int> run() async {
    try {
      await validatePreconditions(
        checkShorebirdInitialized: true,
        checkUserIsAuthenticated: true,
        checkValidators: true,
      );
    } on PreconditionFailedException catch (error) {
      return error.exitCode.code;
    }

    const channelName = 'stable';
    const platform = 'ios';
    final force = results['force'] == true;
    final dryRun = results['dry-run'] == true;
    final flavor = results['flavor'] as String?;
    final target = results['target'] as String?;

    if (force && dryRun) {
      logger.err('Cannot use both --force and --dry-run.');
      return ExitCode.usage.code;
    }

    final shorebirdYaml = getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId(flavor: flavor);
    final App? app;
    try {
      app = await getApp(appId: appId, flavor: flavor);
    } catch (_) {
      return ExitCode.software.code;
    }

    if (app == null) {
      logger.err(
        '''
Could not find app with id: "$appId".
Did you forget to run "shorebird init"?''',
      );
      return ExitCode.software.code;
    }

    final buildProgress = logger.progress('Building release');
    try {
      await buildIpa(flavor: flavor, target: target);
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

    final String releaseVersion;

    final detectReleaseVersionProgress = logger.progress(
      'Detecting release version',
    );
    try {
      final pubspec = getPubspecYaml()!;
      final ipa = _ipaReader.read(
        p.join(
          Directory.current.path,
          'build',
          'ios',
          'ipa',
          '${pubspec.name}.ipa',
        ),
      );
      releaseVersion = ipa.versionNumber;
      detectReleaseVersionProgress.complete();
    } catch (error) {
      detectReleaseVersionProgress.fail(
        'Failed to determine release version: $error',
      );
      return ExitCode.software.code;
    }

    final Release? release;
    try {
      release = await getRelease(appId: appId, releaseVersion: releaseVersion);
    } catch (_) {
      return ExitCode.software.code;
    }

    if (release == null) {
      logger.err(
        '''
Release not found: "$releaseVersion"

Patches can only be published for existing releases.
Please create a release using "shorebird release" and try again.
''',
      );
      return ExitCode.software.code;
    }

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

    final size = formatBytes(aotFile.statSync().size);

    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.id})')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '📺 Channel: ${lightCyan.wrap(channelName)}',
      '''🕹️  Platform: ${lightCyan.wrap(platform)} ${lightCyan.wrap('[arm64 ($size)]')}''',
    ];

    logger.info(
      '''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to publish a new patch!'))}

${summary.join('\n')}
''',
    );

    final needsConfirmation = !force;
    if (needsConfirmation) {
      final confirm = logger.confirm('Would you like to continue?');

      if (!confirm) {
        logger.info('Aborting.');
        return ExitCode.success.code;
      }
    }

    final Patch patch;
    try {
      patch = await createPatch(releaseId: release.id);
    } catch (e) {
      return ExitCode.software.code;
    }

    final codePushClient = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

    // TODO(bryanoltman): check for asset changes

    final createArtifactProgress = logger.progress('Uploading artifacts');
    try {
      await codePushClient.createPatchArtifact(
        patchId: patch.id,
        artifactPath: aotFile.path,
        arch: 'arm64',
        platform: 'ios',
        hash: _hashFn(await aotFile.readAsBytes()),
      );
    } catch (error) {
      createArtifactProgress.fail('$error');
      return ExitCode.software.code;
    }
    createArtifactProgress.complete();

    Channel? channel;
    try {
      channel = await getChannel(appId: appId, name: channelName);
    } catch (_) {
      return ExitCode.software.code;
    }

    if (channel == null) {
      try {
        channel = await createChannel(appId: appId, name: channelName);
      } catch (_) {
        return ExitCode.software.code;
      }
    }

    final publishPatchProgress = logger.progress(
      'Promoting patch to ${channel.name}',
    );
    try {
      await codePushClient.promotePatch(
        patchId: patch.id,
        channelId: channel.id,
      );
      publishPatchProgress.complete();
    } catch (error) {
      publishPatchProgress.fail('$error');
      return ExitCode.software.code;
    }

    logger.success('\n✅ Published Patch!');
    return ExitCode.success.code;
  }
}

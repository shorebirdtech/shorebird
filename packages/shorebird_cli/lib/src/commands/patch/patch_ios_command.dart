import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/formatters/file_size_formatter.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';

/// {@template patch_ios_command}
/// `shorebird patch ios-preview` command.
/// {@endtemplate}
class PatchIosCommand extends ShorebirdCommand
    with
        ShorebirdConfigMixin,
        ShorebirdBuildMixin,
        ShorebirdValidationMixin,
        ShorebirdArtifactMixin {
  /// {@macro patch_ios_command}
  PatchIosCommand({
    super.codePushClientWrapper,
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
  bool get hidden => true;

  @override
  String get name => 'ios';

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

    logger.warn(
      '''iOS support is in an experimental state and will not work without Flutter engine changes that have not yet been published.''',
    );

    const arch = 'aarch64';
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
    final app = await codePushClientWrapper.getApp(appId: appId);

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
      detectReleaseVersionProgress.complete(
        'Detected release version $releaseVersion',
      );
    } catch (error) {
      detectReleaseVersionProgress.fail(
        'Failed to determine release version: $error',
      );
      return ExitCode.software.code;
    }

    final release = await codePushClientWrapper.getRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );

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
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '📺 Channel: ${lightCyan.wrap(channelName)}',
      '''🕹️  Platform: ${lightCyan.wrap(platform)} ${lightCyan.wrap('[$arch (${formatBytes(aotFileSize)})]')}''',
    ];

    logger.info(
      '''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to publish a new patch!'))}

${summary.join('\n')}
''',
    );

    // TODO(bryanoltman): check for asset changes

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
      platform: platform,
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

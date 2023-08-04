import 'dart:async';
import 'dart:io' hide Platform;

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/formatters/file_size_formatter.dart';
import 'package:shorebird_cli/src/ios.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter_manager.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template patch_ios_command}
/// `shorebird patch ios-alpha` command.
/// {@endtemplate}
class PatchIosCommand extends ShorebirdCommand
    with ShorebirdBuildMixin, ShorebirdArtifactMixin {
  /// {@macro patch_ios_command}
  PatchIosCommand({
    HashFunction? hashFn,
    IpaDiffer? ipaDiffer,
  })  : _hashFn = hashFn ?? ((m) => sha256.convert(m).toString()),
        _ipaDiffer = ipaDiffer ?? IpaDiffer() {
    argParser
      ..addOption(
        'release-version',
        help: 'The version of the release (e.g. "1.0.0").',
      )
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
  String get name => 'ios-alpha';

  @override
  String get description =>
      'Publish new patches for a specific iOS release to Shorebird.';

  final HashFunction _hashFn;
  final IpaDiffer _ipaDiffer;

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkShorebirdInitialized: true,
        checkUserIsAuthenticated: true,
        validators: doctor.iosCommandValidators,
        supportedOperatingSystems: {Platform.macOS},
      );
    } on PreconditionFailedException catch (error) {
      return error.exitCode.code;
    }

    showiOSStatusWarning();

    const arch = 'aarch64';
    const channelName = 'stable';
    const releasePlatform = ReleasePlatform.ios;
    final force = results['force'] == true;
    final dryRun = results['dry-run'] == true;
    final flavor = results['flavor'] as String?;
    final target = results['target'] as String?;

    if (force && dryRun) {
      logger.err('Cannot use both --force and --dry-run.');
      return ExitCode.usage.code;
    }

    final shorebirdYaml = shorebirdEnv.getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId(flavor: flavor);
    final app = await codePushClientWrapper.getApp(appId: appId);
    final releases = await codePushClientWrapper.getReleases(appId: appId);
    final releaseVersion = results['release-version'] as String? ??
        await promptForReleaseVersion(releases);

    final release = releases.firstWhereOrNull(
      (r) => r.version == releaseVersion,
    );

    if (releaseVersion == null || release == null) {
      logger.info('No releases found');
      return ExitCode.success.code;
    }

    if (release.platformStatuses[ReleasePlatform.ios] == ReleaseStatus.draft) {
      logger.err('''
Release $releaseVersion is in an incomplete state. It's possible that the original release was terminated or failed to complete.

Please re-run the release command for this version or create a new release.''');
      return ExitCode.software.code;
    }

    final shorebirdFlutterRevision = shorebirdEnv.flutterRevision;
    if (release.flutterRevision != shorebirdFlutterRevision) {
      final installFlutterRevisionProgress = logger.progress(
        'Switching to Flutter revision ${release.flutterRevision}',
      );
      try {
        await shorebirdFlutterManager.installRevision(
          revision: release.flutterRevision,
        );
        installFlutterRevisionProgress.complete();
      } catch (error) {
        installFlutterRevisionProgress.fail('$error');
        return ExitCode.software.code;
      }
    }

    final buildProgress = logger.progress('Building release');
    try {
      await runScoped(
        () => buildIpa(flavor: flavor, target: target),
        values: {
          shorebirdEnvRef.overrideWith(
            () => ShorebirdEnv(
              flutterRevisionOverride: release.flutterRevision,
            ),
          )
        },
      );
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

    final releaseArtifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: 'ipa',
      platform: ReleasePlatform.ios,
    );

    final String ipaPath;
    try {
      ipaPath = getIpaPath();
    } catch (error) {
      logger.err('Could not find ipa file: $error');
      return ExitCode.software.code;
    }

    final shouldContinue =
        await patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
      localArtifact: File(ipaPath),
      releaseArtifactUrl: Uri.parse(releaseArtifact.url),
      archiveDiffer: _ipaDiffer,
      force: force,
    );
    if (!shouldContinue) {
      return ExitCode.success.code;
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
      '''🕹️  Platform: ${lightCyan.wrap(releasePlatform.name)} ${lightCyan.wrap('[$arch (${formatBytes(aotFileSize)})]')}''',
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

  Future<String?> promptForReleaseVersion(List<Release> releases) async {
    if (releases.isEmpty) return null;
    final release = logger.chooseOne(
      'Which release would you like to patch?',
      choices: releases,
      display: (release) => release.version,
    );
    return release.version;
  }
}

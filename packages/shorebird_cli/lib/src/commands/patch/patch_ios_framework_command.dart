import 'dart:io' hide Platform;

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/formatters/file_size_formatter.dart';
import 'package:shorebird_cli/src/ios.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

class PatchIosFrameworkCommand extends ShorebirdCommand
    with ShorebirdBuildMixin, ShorebirdArtifactMixin {
  PatchIosFrameworkCommand({
    HashFunction? hashFn,
    IosArchiveDiffer? archiveDiffer,
  })  : _hashFn = hashFn ?? ((m) => sha256.convert(m).toString()),
        _archiveDiffer = archiveDiffer ?? IosArchiveDiffer() {
    argParser
      ..addOption(
        'release-version',
        help: '''
The version of the associated release (e.g. "1.0.0"). This should be the version
of the iOS app that is using this module.''',
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
  final IosArchiveDiffer _archiveDiffer;

  @override
  String get name => 'ios-framework-alpha';

  @override
  String get description =>
      'Publish new patches for a specific iOS framework release to Shorebird.';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.iosCommandValidators,
        supportedOperatingSystems: {Platform.macOS},
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final force = results['force'] == true;
    final dryRun = results['dry-run'] == true;

    if (force && dryRun) {
      logger.err('Cannot use both --force and --dry-run.');
      return ExitCode.usage.code;
    }

    showiOSStatusWarning();

    const arch = 'aarch64';
    const channelName = 'stable';
    const releasePlatform = ReleasePlatform.ios;
    final shorebirdYaml = shorebirdEnv.getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId();
    final app = await codePushClientWrapper.getApp(appId: appId);
    final releases = await codePushClientWrapper.getReleases(appId: appId);

    if (releases.isEmpty) {
      logger.info('No releases found');
      return ExitCode.success.code;
    }

    final releaseVersion = results['release-version'] as String? ??
        await _promptForReleaseVersion(releases);

    final release = releases.firstWhereOrNull(
      (r) => r.version == releaseVersion,
    );

    if (releaseVersion == null || release == null) {
      logger.info('''
No release found for version $releaseVersion

Available release versions:
${releases.map((r) => r.version).join('\n')}''');
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
        await shorebirdFlutter.installRevision(
          revision: release.flutterRevision,
        );
        installFlutterRevisionProgress.complete();
      } catch (error) {
        installFlutterRevisionProgress.fail('$error');
        return ExitCode.software.code;
      }
    }

    final buildProgress = logger.progress('Building patch');
    try {
      await runScoped(
        buildIosFramework,
        values: {
          shorebirdEnvRef.overrideWith(
            () => ShorebirdEnv(
              flutterRevisionOverride: release.flutterRevision,
            ),
          ),
        },
      );
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

    const zippedFrameworkFileName =
        '${ShorebirdArtifactMixin.appXcframeworkName}.zip';
    final tempDir = Directory.systemTemp.createTempSync();
    final zippedFrameworkPath = p.join(
      tempDir.path,
      zippedFrameworkFileName,
    );
    ZipFileEncoder().zipDirectory(
      Directory(getAppXcframeworkPath()),
      filename: zippedFrameworkPath,
    );

    final releaseArtifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: 'xcframework',
      platform: ReleasePlatform.ios,
    );

    try {
      await patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
        localArtifact: File(zippedFrameworkPath),
        releaseArtifactUrl: Uri.parse(releaseArtifact.url),
        archiveDiffer: _archiveDiffer,
        force: force,
      );
    } on UserCancelledException {
      return ExitCode.success.code;
    } on UnpatchableChangeException {
      logger.info('Exiting.');
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
    final needsConfirmation = !force && !shorebirdEnv.isRunningOnCI;
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

    return ExitCode.success.code;
  }

  Future<String?> _promptForReleaseVersion(List<Release> releases) async {
    if (releases.isEmpty) return null;
    final release = logger.chooseOne(
      'Which release would you like to patch?',
      choices: releases,
      display: (release) => release.version,
    );
    return release.version;
  }
}

import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/formatters/file_size_formatter.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template patch_aar_command}
/// `shorebird patch aar`
/// Create a patch for an Android archive release.
/// {@endtemplate}
class PatchAarCommand extends ShorebirdCommand
    with ShorebirdBuildMixin, ShorebirdArtifactMixin {
  /// {@macro patch_aar_command}
  PatchAarCommand({
    HashFunction? hashFn,
    UnzipFn? unzipFn,
    AndroidArchiveDiffer? archiveDiffer,
  })  : _archiveDiffer = archiveDiffer ?? AndroidArchiveDiffer(),
        _hashFn = hashFn ?? ((m) => sha256.convert(m).toString()),
        _unzipFn = unzipFn ?? extractFileToDisk {
    argParser
      ..addOption(
        'build-number',
        help: 'The build number of the module (e.g. "1.0.0").',
        defaultsTo: '1.0',
      )
      ..addOption(
        'release-version',
        help: '''
The version of the associated release (e.g. "1.0.0"). This should be the version
of the Android app that is using this module.''',
        mandatory: true,
      )
      ..addFlag(
        'allow-native-diffs',
        help: PatchCommand.allowNativeDiffsHelpText,
        negatable: false,
      )
      ..addFlag(
        'allow-asset-diffs',
        help: PatchCommand.allowAssetDiffsHelpText,
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
  String get name => 'aar';

  @override
  String get description =>
      'Publish new patches for a specific Android archive release to Shorebird';

  final AndroidArchiveDiffer _archiveDiffer;
  final HashFunction _hashFn;
  final UnzipFn _unzipFn;

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final dryRun = results['dry-run'] == true;
    final allowAssetDiffs = results['allow-asset-diffs'] == true;
    final allowNativeDiffs = results['allow-native-diffs'] == true;

    await cache.updateAll();

    if (shorebirdEnv.androidPackageName == null) {
      logger.err('Could not find androidPackage in pubspec.yaml.');
      return ExitCode.config.code;
    }

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

    if (release.platformStatuses[ReleasePlatform.android] ==
        ReleaseStatus.draft) {
      logger.err('''
Release $releaseVersion is in an incomplete state. It's possible that the original release was terminated or failed to complete.
Please re-run the release command for this version or create a new release.''');
      return ExitCode.software.code;
    }

    const releasePlatform = ReleasePlatform.android;
    final releaseArtifacts = await codePushClientWrapper.getReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      architectures: AndroidArch.availableAndroidArchs,
      platform: releasePlatform,
    );

    final releaseAarArtifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: 'aar',
      platform: releasePlatform,
    );

    final Map<Arch, String> releaseArtifactPaths;
    try {
      releaseArtifactPaths = await _downloadReleaseArtifacts(
        releaseArtifacts: releaseArtifacts,
      );
    } catch (_) {
      return ExitCode.software.code;
    }

    try {
      await shorebirdFlutter.installRevision(revision: release.flutterRevision);
    } catch (_) {
      return ExitCode.software.code;
    }

    final releaseFlutterShorebirdEnv = shorebirdEnv.copyWith(
      flutterRevisionOverride: release.flutterRevision,
    );

    return await runScoped(
      () async {
        final buildNumber = results['build-number'] as String;
        final buildProgress = logger.progress('Building patch');
        try {
          await buildAar(buildNumber: buildNumber);
          buildProgress.complete();
        } on ProcessException catch (error) {
          buildProgress.fail('Failed to build: ${error.message}');
          return ExitCode.software.code;
        }

        final extractedAarDir = await extractAar(
          packageName: shorebirdEnv.androidPackageName!,
          buildNumber: buildNumber,
          unzipFn: _unzipFn,
        );

        final DiffStatus diffStatus;
        try {
          diffStatus =
              await patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
            localArtifact: File(
              aarArtifactPath(
                packageName: shorebirdEnv.androidPackageName!,
                buildNumber: buildNumber,
              ),
            ),
            releaseArtifact: await artifactManager
                .downloadFile(Uri.parse(releaseAarArtifact.url)),
            archiveDiffer: _archiveDiffer,
            allowAssetChanges: allowAssetDiffs,
            allowNativeChanges: allowNativeDiffs,
          );
        } on UserCancelledException {
          return ExitCode.success.code;
        } on UnpatchableChangeException {
          logger.info('Exiting.');
          return ExitCode.software.code;
        }

        final patchArtifactBundles = await _createPatchArtifacts(
          releaseArtifactPaths: releaseArtifactPaths,
          extractedAarDirectory: extractedAarDir,
        );
        if (patchArtifactBundles == null) {
          return ExitCode.software.code;
        }

        final archMetadata = patchArtifactBundles.keys.map((arch) {
          final size = formatBytes(patchArtifactBundles[arch]!.size);
          return '${arch.name} ($size)';
        });

        if (dryRun) {
          logger
            ..info('No issues detected.')
            ..info('The server may enforce additional checks.');
          return ExitCode.success.code;
        }

        final summary = [
          '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.appId})')}''',
          '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
          '''🕹️  Platform: ${lightCyan.wrap(releasePlatform.name)} ${lightCyan.wrap('[${archMetadata.join(', ')}]')}''',
          '🟢 Track: ${lightCyan.wrap('Production')}',
        ];

        logger.info(
          '''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to publish a new patch!'))}

${summary.join('\n')}
''',
        );

        if (shorebirdEnv.canAcceptUserInput) {
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
          track: DeploymentTrack.production,
          patchArtifactBundles: patchArtifactBundles,
          metadata: CreatePatchMetadata(
            releasePlatform: releasePlatform,
            usedIgnoreAssetChangesFlag: allowAssetDiffs,
            hasAssetChanges: diffStatus.hasAssetChanges,
            usedIgnoreNativeChangesFlag: allowNativeDiffs,
            hasNativeChanges: diffStatus.hasNativeChanges,
            linkPercentage: null,
            environment: BuildEnvironmentMetadata(
              operatingSystem: platform.operatingSystem,
              operatingSystemVersion: platform.operatingSystemVersion,
              shorebirdVersion: packageVersion,
              xcodeVersion: null,
            ),
          ),
        );

        return ExitCode.success.code;
      },
      values: {
        shorebirdEnvRef.overrideWith(() => releaseFlutterShorebirdEnv),
      },
    );
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

  Future<Map<Arch, PatchArtifactBundle>?> _createPatchArtifacts({
    required Map<Arch, String> releaseArtifactPaths,
    required String extractedAarDirectory,
  }) async {
    final patchArtifactBundles = <Arch, PatchArtifactBundle>{};

    final createDiffProgress = logger.progress('Creating artifacts');
    for (final releaseArtifactPath in releaseArtifactPaths.entries) {
      final arch = releaseArtifactPath.key;
      final artifactPath = p.join(
        extractedAarDirectory,
        'jni',
        arch.androidBuildPath,
        'libapp.so',
      );
      logger.detail('Creating artifact for $artifactPath');
      final patchArtifact = File(artifactPath);
      final hash = _hashFn(await patchArtifact.readAsBytes());
      try {
        final diffPath = await artifactManager.createDiff(
          releaseArtifactPath: releaseArtifactPath.value,
          patchArtifactPath: artifactPath,
        );
        patchArtifactBundles[arch] = PatchArtifactBundle(
          arch: arch.arch,
          path: diffPath,
          hash: hash,
          size: await File(diffPath).length(),
        );
      } catch (error) {
        createDiffProgress.fail('$error');
        return null;
      }
    }
    createDiffProgress.complete();

    return patchArtifactBundles;
  }

  Future<Map<Arch, String>> _downloadReleaseArtifacts({
    required Map<Arch, ReleaseArtifact> releaseArtifacts,
  }) async {
    final releaseArtifactPaths = <Arch, String>{};
    final downloadReleaseArtifactProgress = logger.progress(
      'Downloading release artifacts',
    );
    for (final releaseArtifact in releaseArtifacts.entries) {
      try {
        final releaseArtifactFile = await artifactManager.downloadFile(
          Uri.parse(releaseArtifact.value.url),
        );
        releaseArtifactPaths[releaseArtifact.key] = releaseArtifactFile.path;
      } catch (error) {
        downloadReleaseArtifactProgress.fail('$error');
        rethrow;
      }
    }

    downloadReleaseArtifactProgress.complete();
    return releaseArtifactPaths;
  }
}

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
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/formatters/file_size_formatter.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
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

    final force = results['force'] == true;
    final dryRun = results['dry-run'] == true;

    if (force && dryRun) {
      logger.err('Cannot use both --force and --dry-run.');
      return ExitCode.usage.code;
    }

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

    const platform = ReleasePlatform.android;
    final releaseArtifacts = await codePushClientWrapper.getReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      architectures: architectures,
      platform: platform,
    );

    final releaseAarArtifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: 'aar',
      platform: platform,
    );

    final Map<Arch, String> releaseArtifactPaths;
    try {
      releaseArtifactPaths = await _downloadReleaseArtifacts(
        releaseArtifacts: releaseArtifacts,
      );
    } catch (_) {
      return ExitCode.software.code;
    }

    final buildNumber = results['build-number'] as String;
    final buildProgress = logger.progress('Building patch');
    try {
      await runScoped(
        () => buildAar(buildNumber: buildNumber),
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

    final extractedAarDir = await extractAar(
      packageName: shorebirdEnv.androidPackageName!,
      buildNumber: buildNumber,
      unzipFn: _unzipFn,
    );

    try {
      await patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
        localArtifact: File(
          aarArtifactPath(
            packageName: shorebirdEnv.androidPackageName!,
            buildNumber: buildNumber,
          ),
        ),
        releaseArtifactUrl: Uri.parse(releaseAarArtifact.url),
        archiveDiffer: _archiveDiffer,
        force: force,
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
      final name = arch.name;
      final size = formatBytes(patchArtifactBundles[arch]!.size);
      return '$name ($size)';
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
      '''🕹️  Platform: ${lightCyan.wrap(platform.name)} ${lightCyan.wrap('[${archMetadata.join(', ')}]')}''',
      '🟢 Track: ${lightCyan.wrap('Production')}',
    ];

    logger.info(
      '''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to publish a new patch!'))}

${summary.join('\n')}
''',
    );

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
      platform: platform,
      track: DeploymentTrack.production,
      patchArtifactBundles: patchArtifactBundles,
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

  Future<Map<Arch, PatchArtifactBundle>?> _createPatchArtifacts({
    required Map<Arch, String> releaseArtifactPaths,
    required String extractedAarDirectory,
  }) async {
    final patchArtifactBundles = <Arch, PatchArtifactBundle>{};

    final createDiffProgress = logger.progress('Creating artifacts');
    for (final releaseArtifactPath in releaseArtifactPaths.entries) {
      final archMetadata = architectures[releaseArtifactPath.key]!;
      final artifactPath = p.join(
        extractedAarDirectory,
        'jni',
        archMetadata.path,
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
        patchArtifactBundles[releaseArtifactPath.key] = PatchArtifactBundle(
          arch: archMetadata.arch,
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
        final releaseArtifactPath = await artifactManager.downloadFile(
          Uri.parse(releaseArtifact.value.url),
        );
        releaseArtifactPaths[releaseArtifact.key] = releaseArtifactPath;
      } catch (error) {
        downloadReleaseArtifactProgress.fail('$error');
        rethrow;
      }
    }

    downloadReleaseArtifactProgress.complete();
    return releaseArtifactPaths;
  }
}

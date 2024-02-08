import 'dart:io' hide Platform;
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/executables/aot_tools.dart';
import 'package:shorebird_cli/src/formatters/file_size_formatter.dart';
import 'package:shorebird_cli/src/ios.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
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

  String get _buildDirectory => p.join(
        shorebirdEnv.getShorebirdProjectRoot()!.path,
        'build',
      );

  String get _vmcodeOutputPath => p.join(
        _buildDirectory,
        'out.vmcode',
      );

  @override
  String get name => 'ios-framework';

  @override
  List<String> get aliases => ['ios-framework-alpha'];

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

    final currentFlutterRevision = shorebirdEnv.flutterRevision;
    if (release.flutterRevision != currentFlutterRevision) {
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

    final File aotSnapshotFile;
    try {
      final newestDillFile = newestAppDill();
      aotSnapshotFile = await buildElfAotSnapshot(
        appDillPath: newestDillFile.path,
        outFilePath: p.join(
          shorebirdEnv.getShorebirdProjectRoot()!.path,
          'build',
          'out.aot',
        ),
      );
    } catch (error) {
      buildProgress.fail('$error');
      return ExitCode.software.code;
    }

    buildProgress.complete();

    final releaseArtifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: 'xcframework',
      platform: ReleasePlatform.ios,
    );

    final downloadProgress = logger.progress('Downloading release artifact');
    final File releaseArtifactZipFile;
    try {
      releaseArtifactZipFile = await artifactManager.downloadFile(
        Uri.parse(releaseArtifact.url),
      );
      if (!releaseArtifactZipFile.existsSync()) {
        throw Exception('Failed to download release artifact');
      }
    } catch (error) {
      downloadProgress.fail('$error');
      return ExitCode.software.code;
    }
    downloadProgress.complete();

    try {
      await patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
        localArtifactDirectory: Directory(getAppXcframeworkPath()),
        releaseArtifact: releaseArtifactZipFile,
        archiveDiffer: _archiveDiffer,
        force: force,
      );
    } on UserCancelledException {
      return ExitCode.success.code;
    } on UnpatchableChangeException {
      logger.info('Exiting.');
      return ExitCode.software.code;
    }

    final extractZip = artifactManager.extractZip;
    final unzipProgress = logger.progress('Extracting release artifact');
    final releaseXcframeworkPath = await Isolate.run(() async {
      final tempDir = Directory.systemTemp.createTempSync();
      await extractZip(
        zipFile: releaseArtifactZipFile,
        outputDirectory: tempDir,
      );
      return tempDir.path;
    });

    unzipProgress
        .complete('Extracted release artifact to $releaseXcframeworkPath');
    final releaseArtifactFile = File(
      p.join(
        releaseXcframeworkPath,
        'ios-arm64',
        'App.framework',
        'App',
      ),
    );

    final useLinker = engineConfig.localEngine != null ||
        !preLinkerFlutterRevisions.contains(release.flutterRevision);
    if (useLinker) {
      // Because aot-tools is versioned with the engine, we need to use the
      // original Flutter revision to link the patch. We have already switched
      // to and from the release's Flutter revision before and could
      // theoretically have just stayed on that revision until after _runLinker,
      // but this approach makes it less likely that we will leave the user on
      // a different version of Flutter than they started with if something
      // goes wrong.
      if (release.flutterRevision != currentFlutterRevision) {
        await shorebirdFlutter.useRevision(revision: release.flutterRevision);
      }
      final exitCode = await _runLinker(
        aotSnapshot: aotSnapshotFile,
        releaseArtifact: releaseArtifactFile,
      );
      if (release.flutterRevision != currentFlutterRevision) {
        await shorebirdFlutter.useRevision(revision: currentFlutterRevision);
      }
      if (exitCode != ExitCode.success.code) {
        return exitCode;
      }
    }

    final patchBuildFile =
        useLinker ? File(_vmcodeOutputPath) : aotSnapshotFile;
    final File patchFile;
    if (await aotTools.isGeneratePatchDiffBaseSupported()) {
      final patchBaseProgress = logger.progress('Generating patch diff base');
      final analyzeSnapshotPath = shorebirdArtifacts.getArtifactPath(
        artifact: ShorebirdArtifact.analyzeSnapshot,
      );

      final File patchBaseFile;
      try {
        // If the aot_tools executable supports the dump_blobs command, we
        // can generate a stable diff base and use that to create a patch.
        patchBaseFile = await aotTools.generatePatchDiffBase(
          analyzeSnapshotPath: analyzeSnapshotPath,
          releaseSnapshot: releaseArtifactFile,
        );
        patchBaseProgress.complete();
      } catch (error) {
        patchBaseProgress.fail('$error');
        return ExitCode.software.code;
      }

      patchFile = File(
        await artifactManager.createDiff(
          releaseArtifactPath: patchBaseFile.path,
          patchArtifactPath: patchBuildFile.path,
        ),
      );
    } else {
      patchFile = patchBuildFile;
    }

    if (dryRun) {
      logger
        ..info('No issues detected.')
        ..info('The server may enforce additional checks.');
      return ExitCode.success.code;
    }

    final patchFileSize = patchFile.statSync().size;
    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('($appId)')}''',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '''🕹️  Platform: ${lightCyan.wrap(releasePlatform.name)} ${lightCyan.wrap('[$arch (${formatBytes(patchFileSize)})]')}''',
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
      platform: releasePlatform,
      track: DeploymentTrack.production,
      patchArtifactBundles: {
        Arch.arm64: PatchArtifactBundle(
          arch: arch,
          path: patchFile.path,
          hash: _hashFn(patchBuildFile.readAsBytesSync()),
          size: patchFileSize,
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

  Future<int> _runLinker({
    required File aotSnapshot,
    required File releaseArtifact,
  }) async {
    if (!aotSnapshot.existsSync()) {
      logger.err('Unable to find patch AOT file at ${aotSnapshot.path}');
      return ExitCode.software.code;
    }

    final analyzeSnapshot = File(
      shorebirdArtifacts.getArtifactPath(
        artifact: ShorebirdArtifact.analyzeSnapshot,
      ),
    );

    if (!analyzeSnapshot.existsSync()) {
      logger.err('Unable to find analyze_snapshot at ${analyzeSnapshot.path}');
      return ExitCode.software.code;
    }

    final linkProgress = logger.progress('Linking AOT files');
    try {
      await aotTools.link(
        base: releaseArtifact.path,
        patch: aotSnapshot.path,
        analyzeSnapshot: analyzeSnapshot.path,
        outputPath: _vmcodeOutputPath,
        workingDirectory: _buildDirectory,
      );
    } catch (error) {
      linkProgress.fail('Failed to link AOT files: $error');
      return ExitCode.software.code;
    }

    linkProgress.complete();
    return ExitCode.success.code;
  }
}

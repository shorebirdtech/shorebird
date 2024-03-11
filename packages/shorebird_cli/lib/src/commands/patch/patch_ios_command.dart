import 'dart:async';
import 'dart:io' hide Platform;
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
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

/// {@template patch_ios_command}
/// `shorebird patch ios` command.
/// {@endtemplate}
class PatchIosCommand extends ShorebirdCommand
    with ShorebirdBuildMixin, ShorebirdArtifactMixin {
  /// {@macro patch_ios_command}
  PatchIosCommand({
    HashFunction? hashFn,
    IosArchiveDiffer? archiveDiffer,
  })  : _hashFn = hashFn ?? ((m) => sha256.convert(m).toString()),
        _archiveDiffer = archiveDiffer ?? IosArchiveDiffer() {
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
        'release-version',
        help: '''
The version of the release being patched (e.g. "1.0.0+1").
        
If this option is not provided, the version number will be determined from the patch artifact.''',
      )
      ..addFlag(
        'codesign',
        help: 'Codesign the application bundle.',
        defaultsTo: true,
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
      )
      ..addFlag(
        'staging',
        negatable: false,
        help: 'Whether to publish the patch to the staging environment.',
      );
  }

  @override
  String get name => 'ios';

  @override
  List<String> get aliases => ['ios-alpha'];

  @override
  String get description =>
      'Publish new patches for a specific iOS release to Shorebird.';

  final HashFunction _hashFn;
  final IosArchiveDiffer _archiveDiffer;

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

    final force = results['force'] == true;
    final dryRun = results['dry-run'] == true;
    final isStaging = results['staging'] == true;

    if (force && dryRun) {
      logger.err('Cannot use both --force and --dry-run.');
      return ExitCode.usage.code;
    }

    const arch = 'aarch64';
    const releasePlatform = ReleasePlatform.ios;
    final flavor = results.findOption('flavor', argParser: argParser);
    final target = results.findOption('target', argParser: argParser);
    final shorebirdYaml = shorebirdEnv.getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId(flavor: flavor);
    final app = await codePushClientWrapper.getApp(appId: appId);
    var hasBuiltWithLatestFlutter = false;

    final String releaseVersion;
    final argReleaseVersion = results['release-version'] as String?;
    if (argReleaseVersion != null) {
      logger.detail('Using release version $argReleaseVersion from argument.');
      releaseVersion = argReleaseVersion;
    } else {
      logger.detail('No release version provided. Determining from archive.');
      try {
        await _buildPatch(flavor: flavor, target: target);
      } catch (_) {
        return ExitCode.software.code;
      }
      hasBuiltWithLatestFlutter = true;

      final archivePath = getXcarchiveDirectory()?.path;
      if (archivePath == null) {
        logger.err('Unable to find .xcarchive directory');
        return ExitCode.software.code;
      }

      final plistFile = File(p.join(archivePath, 'Info.plist'));
      if (!plistFile.existsSync()) {
        logger.err('No Info.plist file found at ${plistFile.path}.');
        return ExitCode.software.code;
      }

      final plist = Plist(file: plistFile);
      try {
        releaseVersion = plist.versionNumber;
      } catch (error) {
        logger.err(
          'Failed to determine release version from ${plistFile.path}: $error',
        );
        return ExitCode.software.code;
      }

      logger.info('Detected release version $releaseVersion');
    }

    final release = await codePushClientWrapper.getRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );

    if (release.platformStatuses[ReleasePlatform.ios] == null) {
      logger.err('No iOS release found for $releaseVersion.');
      return ExitCode.software.code;
    } else if (release.platformStatuses[ReleasePlatform.ios] ==
        ReleaseStatus.draft) {
      logger.err('''
Release $releaseVersion is in an incomplete state. It's possible that the original release was terminated or failed to complete.
Please re-run the release command for this version or create a new release.''');
      return ExitCode.software.code;
    }

    final currentFlutterRevision = shorebirdEnv.flutterRevision;
    if (release.flutterRevision != currentFlutterRevision) {
      logger.info('''

The release you are trying to patch was built with a different version of Flutter.

Release Flutter Revision: ${release.flutterRevision}
Current Flutter Revision: $currentFlutterRevision
''');

      var flutterVersionProgress = logger.progress(
        'Switching to Flutter revision ${release.flutterRevision}',
      );
      await shorebirdFlutter.useRevision(revision: release.flutterRevision);
      flutterVersionProgress.complete();

      try {
        await _buildPatch(flavor: flavor, target: target);
      } catch (_) {
        return ExitCode.software.code;
      } finally {
        flutterVersionProgress = logger.progress(
          '''Switching back to original Flutter revision $currentFlutterRevision''',
        );
        await shorebirdFlutter.useRevision(revision: currentFlutterRevision);
        flutterVersionProgress.complete();
      }
    } else if (!hasBuiltWithLatestFlutter) {
      // If we haven't already built the patch with the latest version of
      // Flutter (i.e., if the release version was provided as an argument and
      // we didn't need to build the patch to determine the release version),
      // build it now.
      try {
        await _buildPatch(flavor: flavor, target: target);
      } catch (_) {
        return ExitCode.software.code;
      }
    }

    final archivePath = getXcarchiveDirectory()?.path;
    if (archivePath == null) {
      logger.err('Unable to find .xcarchive directory');
      return ExitCode.software.code;
    }

    final releaseArtifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: 'xcarchive',
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

    final DiffStatus diffStatus;
    try {
      diffStatus =
          await patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
        localArtifactDirectory: Directory(archivePath),
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
    final releaseXcarchivePath = await Isolate.run(() async {
      final tempDir = Directory.systemTemp.createTempSync();
      await extractZip(
        zipFile: releaseArtifactZipFile,
        outputDirectory: tempDir,
      );
      return tempDir.path;
    });
    unzipProgress.complete();
    final appDirectory =
        getAppDirectory(xcarchiveDirectory: Directory(releaseXcarchivePath));
    if (appDirectory == null) {
      logger.err('Unable to find release artifact .app directory');
      return ExitCode.software.code;
    }
    final releaseArtifactFile = File(
      p.join(
        appDirectory.path,
        'Frameworks',
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
        releaseArtifact: releaseArtifactFile,
      );
      if (release.flutterRevision != currentFlutterRevision) {
        await shorebirdFlutter.useRevision(revision: currentFlutterRevision);
      }
      if (exitCode != ExitCode.success.code) {
        return exitCode;
      }
    }

    if (dryRun) {
      logger
        ..info('No issues detected.')
        ..info('The server may enforce additional checks.');
      return ExitCode.success.code;
    }

    final patchBuildFile = File(useLinker ? _vmcodeOutputPath : _aotOutputPath);
    final File patchFile;
    if (useLinker && await aotTools.isGeneratePatchDiffBaseSupported()) {
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

    final patchFileSize = patchFile.statSync().size;

    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('($appId)')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '''🕹️  Platform: ${lightCyan.wrap(releasePlatform.name)} ${lightCyan.wrap('[$arch (${formatBytes(patchFileSize)})]')}''',
      if (isStaging)
        '🟠 Track: ${lightCyan.wrap('Staging')}'
      else
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
      wasForced: force,
      hasAssetChanges: diffStatus.hasAssetChanges,
      hasNativeChanges: diffStatus.hasNativeChanges,
      platform: releasePlatform,
      track: isStaging ? DeploymentTrack.staging : DeploymentTrack.production,
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

  String get _buildDirectory => p.join(
        shorebirdEnv.getShorebirdProjectRoot()!.path,
        'build',
      );

  String get _aotOutputPath => p.join(
        _buildDirectory,
        'out.aot',
      );

  String get _vmcodeOutputPath => p.join(
        _buildDirectory,
        'out.vmcode',
      );

  Future<void> _buildPatch({
    required String? flavor,
    required String? target,
  }) async {
    final shouldCodesign = results['codesign'] == true;
    final buildProgress = logger.progress('Building patch');
    try {
      // If buildIpa is called with a different codesign value than the release
      // was, we will erroneously report native diffs.
      await buildIpa(codesign: shouldCodesign, flavor: flavor, target: target);
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      rethrow;
    } on BuildException catch (error) {
      buildProgress.fail('Failed to build IPA');
      logger.err(error.message);
      rethrow;
    }

    try {
      final newestDillFile = newestAppDill();
      await buildElfAotSnapshot(
        appDillPath: newestDillFile.path,
        outFilePath: _aotOutputPath,
      );
    } catch (error) {
      buildProgress.fail('$error');
      rethrow;
    }

    buildProgress.complete();
  }

  Future<int> _runLinker({required File releaseArtifact}) async {
    final patch = File(_aotOutputPath);

    if (!patch.existsSync()) {
      logger.err('Unable to find patch AOT file at ${patch.path}');
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
        patch: patch.path,
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

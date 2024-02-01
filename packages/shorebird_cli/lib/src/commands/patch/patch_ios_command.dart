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

/// Revisions of Flutter that were released before the linker was enabled.
const preLinkerFlutterRevisions = <String>{
  '45d609090a2313d47a4e657d449ff25710abc853',
  '0b0086ffa92c25c22f50cbadc3851054f08a9cd8',
  'a3d5f7c614aa1cc4d6cb1506e74fd1c81678e68e',
  'b7ad8d5759c4889ea323948fe589c69a39c26135',
  '49b602f7fae8f5bcd8de9547f31928058cbd768e',
  '6116674ab0d6449104f9f342d96cef0abe30a9a1',
  'ba444de6ceb9313320a70563d7b6203344e0cd87',
  '0671f4f9fb2589055d64537e03d7733448b3488b',
  '1cf1fef6a503672b919a4390ed61320daac07139',
  '5de12cedfe6002b79183bc59af04561a98c8aa82',
  '9486b6431e6c808c4e131f134b5d88017b3c32ab',
  '2e05c41803943a1e81360ae97c75a229c1fb55ef',
  '0e2d280277cf9f60f7ba802a59f9fd187ffdd050',
  '628a3eba4e0aba5e6f92c87b320f3c99afb85e61',
  '3612c8dc659dd7866578b19396efcb63cad71bef',
  'd84d466eacbeb47d6e81e960c22c6fdfe5a3917d',
  '8576da53c568d904f464b8aeac105c8790285d32',
  'd93eb3686c60b626691c8020d7353ea22a0f5ea2',
  '39df2792f537b1fc62a9c668a6990f585bd91456',
  '03e895ee09dfbb9c18681d103f4b27671ff65429',
  'b9b23902966504a9778f4c07e3a3487fa84dcb2a',
  '02454bae6bf3bef150171c9ce299279e8b875b2e',
  '8861a600668dbc4d9ca131f5158871bc0523f428',
  'ef4b661ddc0c71b738432ae59c6bc573e917854b',
  '47db6d73cfe3227129a510445dd82c45c2dbe347',
  '7b63f1bac9879c2b00f02bc8d404ffc4c7f24ca2',
  '012153de178d4a51cd6f9adc792ad63ae3cfb1b3',
  '83305b5088e6fe327fb3334a73ff190828d85713',
  '225beb5302e2f03603a775d23be11d96ae253ab1',
  '402424409c29c28ed69e14cbb39f0a7424a47e16',
  'b27620fa7dca89c742c12b1277571f7a0d6a9740',
  '447487a4d2f1a73376e82c61e708f75e315cdaa5',
  'c0e52af9097e779671591ea105031920f24da4d5',
  '211d78f6d673fdc6f728217c8f999827c040cd23',
  'efce3391b9c729e2899e4e1383df718c4445c3ae',
  '0f62afa7ad2eaa2fa44ff28278d6c6eaf81f327e',
  '0fc414cbc33ee017ad509671009e8b242539ea16',
  '6b9b5ff45af7a1ef864038dd7d0c32b620b357c6',
  '7cd77f78a51576652edc337817152abf4217a257',
  '5567fb431a2ddbb70c05ff7cd8fcd58bb91f2dbc',
  '914d5b5fcacc794fd0319f2928ceb514e1e0da33',
  'e744c831b8355bcb9f3b541d42431d9145eea677',
  '1a6115bebe31e63508c312d14e69e973e1a59dbf',
};

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

    try {
      await _buildPatch(flavor: flavor, target: target);
    } catch (_) {
      return ExitCode.software.code;
    }

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
    final String releaseVersion;
    final argReleaseVersion = results['release-version'] as String?;
    if (argReleaseVersion != null) {
      logger.detail('Using release version $argReleaseVersion from argument.');
      releaseVersion = argReleaseVersion;
    } else {
      logger.detail('No release version provided. Determining from archive.');
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

    final originalFlutterRevision = shorebirdEnv.flutterRevision;
    if (release.flutterRevision != originalFlutterRevision) {
      logger.info('''

The release you are trying to patch was built with a different version of Flutter.

Release Flutter Revision: ${release.flutterRevision}
Current Flutter Revision: $originalFlutterRevision
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
          '''Switching back to original Flutter revision $originalFlutterRevision''',
        );
        await shorebirdFlutter.useRevision(revision: originalFlutterRevision);
        flutterVersionProgress.complete();
      }
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

    try {
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
      if (release.flutterRevision != originalFlutterRevision) {
        await shorebirdFlutter.useRevision(revision: release.flutterRevision);
      }
      final exitCode = await _runLinker(
        releaseArtifact: releaseArtifactFile,
      );
      if (release.flutterRevision != originalFlutterRevision) {
        await shorebirdFlutter.useRevision(revision: originalFlutterRevision);
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

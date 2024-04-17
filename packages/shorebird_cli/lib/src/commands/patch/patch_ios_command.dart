import 'dart:async';
import 'dart:io' hide Platform;

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/formatters/file_size_formatter.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/version.dart';
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
      ..addOption(
        exportOptionsPlistArgName,
        help:
            '''Export an IPA with these options. See "xcodebuild -h" for available exportOptionsPlist keys.''',
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

  // Link percentage that is considered the minimum before a user might notice.
  // Our early testing has shown that about:
  // - 1/3rd of patches link at 99%
  // - 1/3rd of patches link between 20% and 99%
  // - 1/3rd of patches link below 20%
  // Most lowering is likely due to:
  // https://github.com/shorebirdtech/shorebird/issues/1825
  static const double minLinkPercentage = 75;

  static String lowLinkPercentageWarning(double linkPercentage) {
    return '''
${lightCyan.wrap('shorebird patch')} was only able to share ${linkPercentage.toStringAsFixed(1)}% of Dart code with the released app.
This means the patched code may execute slower than expected.
https://docs.shorebird.dev/status#link-percentage-ios
''';
  }

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

    final allowAssetDiffs = results['allow-asset-diffs'] == true;
    final allowNativeDiffs = results['allow-native-diffs'] == true;
    final dryRun = results['dry-run'] == true;
    final isStaging = results['staging'] == true;

    const arch = 'aarch64';
    const releasePlatform = ReleasePlatform.ios;
    final flavor = results.findOption('flavor', argParser: argParser);
    final target = results.findOption('target', argParser: argParser);
    final shorebirdYaml = shorebirdEnv.getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId(flavor: flavor);
    final app = await codePushClientWrapper.getApp(appId: appId);
    var hasBuiltWithActiveFlutter = false;

    final File exportOptionsPlist;
    try {
      exportOptionsPlist = ios.exportOptionsPlistFromArgs(results);
    } catch (error) {
      logger.err('$error');
      return ExitCode.usage.code;
    }

    final String releaseVersion;
    final argReleaseVersion = results['release-version'] as String?;
    if (argReleaseVersion != null) {
      logger.detail('Using release version $argReleaseVersion from argument.');
      releaseVersion = argReleaseVersion;
    } else {
      logger.detail('No release version provided. Determining from archive.');
      try {
        await _buildPatch(
          exportOptionsPlist: exportOptionsPlist,
          flavor: flavor,
          target: target,
        );
      } catch (_) {
        return ExitCode.software.code;
      }
      hasBuiltWithActiveFlutter = true;

      try {
        releaseVersion = _readVersionFromPlist();
        logger.info('Detected release version $releaseVersion');
      } on _ReadVersionException catch (error) {
        logger.err(error.message);
        return ExitCode.software.code;
      }
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
      logger.info(
        '''

The release you are trying to patch was built with a different version of Flutter.

Release Flutter Revision: ${release.flutterRevision}
Current Flutter Revision: $currentFlutterRevision
''',
      );
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
        if (!hasBuiltWithActiveFlutter ||
            release.flutterRevision != currentFlutterRevision) {
          try {
            await _buildPatch(
              exportOptionsPlist: exportOptionsPlist,
              flavor: flavor,
              target: target,
            );
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

        final downloadProgress =
            logger.progress('Downloading release artifact');
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
            allowAssetChanges: allowAssetDiffs,
            allowNativeChanges: allowNativeDiffs,
          );
        } on UserCancelledException {
          return ExitCode.success.code;
        } on UnpatchableChangeException {
          logger.info('Exiting.');
          return ExitCode.software.code;
        }

        final unzipProgress = logger.progress('Extracting release artifact');
        final tempDir = Directory.systemTemp.createTempSync();
        await artifactManager.extractZip(
          zipFile: releaseArtifactZipFile,
          outputDirectory: tempDir,
        );
        final releaseXcarchivePath = tempDir.path;

        unzipProgress.complete();
        final appDirectory = getAppDirectory(
          xcarchiveDirectory: Directory(releaseXcarchivePath),
        );
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

        double? percentLinked;
        final useLinker = AotTools.usesLinker(release.flutterRevision);
        if (useLinker) {
          final (:exitCode, :linkPercentage) = await _runLinker(
            releaseArtifact: releaseArtifactFile,
          );

          if (exitCode != ExitCode.success.code) return exitCode;

          if (linkPercentage != null && linkPercentage < minLinkPercentage) {
            logger.warn(lowLinkPercentageWarning(linkPercentage));
          }
          percentLinked = linkPercentage;
        }

        if (dryRun) {
          logger
            ..info('No issues detected.')
            ..info('The server may enforce additional checks.');
          return ExitCode.success.code;
        }

        final patchBuildFile =
            File(useLinker ? _vmcodeOutputPath : _aotOutputPath);
        final File patchFile;
        if (useLinker && await aotTools.isGeneratePatchDiffBaseSupported()) {
          final patchBaseProgress =
              logger.progress('Generating patch diff base');
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
          if (percentLinked != null)
            '''🔗 Running ${lightCyan.wrap('${percentLinked.toStringAsFixed(1)}%')} on CPU''',
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
          track:
              isStaging ? DeploymentTrack.staging : DeploymentTrack.production,
          patchArtifactBundles: {
            Arch.arm64: PatchArtifactBundle(
              arch: arch,
              path: patchFile.path,
              hash: _hashFn(patchBuildFile.readAsBytesSync()),
              size: patchFileSize,
            ),
          },
          metadata: CreatePatchMetadata(
            releasePlatform: releasePlatform,
            usedIgnoreAssetChangesFlag: allowAssetDiffs,
            hasAssetChanges: diffStatus.hasAssetChanges,
            usedIgnoreNativeChangesFlag: allowNativeDiffs,
            hasNativeChanges: diffStatus.hasNativeChanges,
            linkPercentage: percentLinked,
            environment: BuildEnvironmentMetadata(
              operatingSystem: platform.operatingSystem,
              operatingSystemVersion: platform.operatingSystemVersion,
              shorebirdVersion: packageVersion,
              xcodeVersion: await xcodeBuild.version(),
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

  String _readVersionFromPlist() {
    final archivePath = getXcarchiveDirectory()?.path;
    if (archivePath == null) {
      throw _ReadVersionException('Unable to find .xcarchive directory');
    }

    final plistFile = File(p.join(archivePath, 'Info.plist'));
    if (!plistFile.existsSync()) {
      throw _ReadVersionException(
        'No Info.plist file found at ${plistFile.path}.',
      );
    }

    final plist = Plist(file: plistFile);
    try {
      return plist.versionNumber;
    } catch (error) {
      throw _ReadVersionException(
        'Failed to determine release version from ${plistFile.path}: $error',
      );
    }
  }

  Future<void> _buildPatch({
    required File exportOptionsPlist,
    required String? flavor,
    required String? target,
  }) async {
    final shouldCodesign = results['codesign'] == true;
    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();
    final buildProgress = logger.progress(
      'Building patch with Flutter $flutterVersionString',
    );
    try {
      // If buildIpa is called with a different codesign value than the release
      // was, we will erroneously report native diffs.
      await buildIpa(
        codesign: shouldCodesign,
        exportOptionsPlist: exportOptionsPlist,
        flavor: flavor,
        target: target,
      );
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

  Future<_LinkResult> _runLinker({required File releaseArtifact}) async {
    final patch = File(_aotOutputPath);

    if (!patch.existsSync()) {
      logger.err('Unable to find patch AOT file at ${patch.path}');
      return (exitCode: ExitCode.software.code, linkPercentage: null);
    }

    final analyzeSnapshot = File(
      shorebirdArtifacts.getArtifactPath(
        artifact: ShorebirdArtifact.analyzeSnapshot,
      ),
    );

    if (!analyzeSnapshot.existsSync()) {
      logger.err('Unable to find analyze_snapshot at ${analyzeSnapshot.path}');
      return (exitCode: ExitCode.software.code, linkPercentage: null);
    }

    final genSnapshot = shorebirdArtifacts.getArtifactPath(
      artifact: ShorebirdArtifact.genSnapshot,
    );

    final linkProgress = logger.progress('Linking AOT files');
    double? linkPercentage;
    try {
      linkPercentage = await aotTools.link(
        base: releaseArtifact.path,
        patch: patch.path,
        analyzeSnapshot: analyzeSnapshot.path,
        genSnapshot: genSnapshot,
        outputPath: _vmcodeOutputPath,
        workingDirectory: _buildDirectory,
        kernel: newestAppDill().path,
      );
    } catch (error) {
      linkProgress.fail('Failed to link AOT files: $error');
      return (exitCode: ExitCode.software.code, linkPercentage: null);
    }
    linkProgress.complete();
    return (exitCode: ExitCode.success.code, linkPercentage: linkPercentage);
  }
}

typedef _LinkResult = ({int exitCode, double? linkPercentage});

/// {@template _ReadVersionException}
/// Exception thrown when the release version cannot be determined.
/// {@endtemplate}
class _ReadVersionException implements Exception {
  /// {@macro _ReadVersionException}
  _ReadVersionException(this.message);

  final String message;
}

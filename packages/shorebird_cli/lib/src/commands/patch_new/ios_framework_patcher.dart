import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive/directory_archive.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/ios_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch_new/patch_new.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_linker.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template ios_framework_patcher}
/// Functions to patch an iOS Framework release.
/// {@endtemplate}
class IosFrameworkPatcher extends Patcher {
  /// {@macro ios_framework_patcher}
  IosFrameworkPatcher({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  String get _buildDirectory => p.join(
        shorebirdEnv.getShorebirdProjectRoot()!.path,
        'build',
      );

  String get _vmcodeOutputPath => p.join(
        _buildDirectory,
        'out.vmcode',
      );

  @override
  ArchiveDiffer get archiveDiffer => IosArchiveDiffer();

  @override
  String get primaryReleaseArtifactArch => 'xcframework';

  @override
  ReleaseType get releaseType => ReleaseType.iosFramework;

  @visibleForTesting
  double? lastBuildLinkPercentage;

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.iosCommandValidators,
        supportedOperatingSystems: {Platform.macOS},
      );
    } on PreconditionFailedException catch (e) {
      exit(e.exitCode.code);
    }
  }

  @override
  Future<void> assertArgsAreValid() async {
    if (!argResults.wasParsed('release-version')) {
      logger.err('Missing required argument: --release-version');
      exit(ExitCode.usage.code);
    }
  }

  @override
  Future<File> buildPatchArtifact() async {
    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();
    final buildProgress = logger.progress(
      'Building patch with Flutter $flutterVersionString',
    );
    try {
      await artifactBuilder.buildIosFramework();
    } on ArtifactBuildException catch (error) {
      buildProgress.fail(error.message);
      exit(ExitCode.software.code);
    }
    try {
      final newestDillFile = artifactManager.newestAppDill();
      await artifactBuilder.buildElfAotSnapshot(
        appDillPath: newestDillFile.path,
        outFilePath: p.join(
          shorebirdEnv.getShorebirdProjectRoot()!.path,
          'build',
          'out.aot',
        ),
      );
    } catch (error) {
      buildProgress.fail('$error');
      exit(ExitCode.software.code);
    }

    buildProgress.complete();

    return Directory(
      p.join(
        artifactManager.getAppXcframeworkDirectory().path,
        ArtifactManager.appXcframeworkName,
      ),
    ).zipToTempFile();
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
  }) async {
    final releaseArtifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: releaseId,
      arch: 'xcframework',
      platform: ReleasePlatform.ios,
    );

    final downloadProgress = logger.progress('Downloading release artifact');
    final File releaseArtifactZipFile;
    try {
      releaseArtifactZipFile = await artifactManager.downloadFile(
        Uri.parse(releaseArtifact.url),
      );
    } catch (error) {
      downloadProgress.fail('$error');
      exit(ExitCode.software.code);
    }
    downloadProgress.complete();

    final unzipProgress = logger.progress('Extracting release artifact');
    final tempDir = Directory.systemTemp.createTempSync();
    await artifactManager.extractZip(
      zipFile: releaseArtifactZipFile,
      outputDirectory: tempDir,
    );
    final releaseXcframeworkPath = tempDir.path;

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

    final LinkResult linkResult;

    final linkProgress = logger.progress('Linking patch artifact');
    try {
      linkResult = await shorebirdLinker.linkPatchArtifactIfPossible(
        releaseArtifact: releaseArtifactFile,
        patchBuildFile: File(
          p.join(
            shorebirdEnv.getShorebirdProjectRoot()!.path,
            'build',
            'out.aot',
          ),
        ),
      );
    } catch (e) {
      linkProgress.fail('$e');
      exit(ExitCode.software.code);
    }

    lastBuildLinkPercentage = linkResult.linkPercentage;

    return {
      Arch.arm64: PatchArtifactBundle(
        arch: 'aarch64',
        path: linkResult.patchBuildFile.path,
        hash: sha256
            .convert(linkResult.patchBuildFile.readAsBytesSync())
            .toString(),
        size: linkResult.patchBuildFile.statSync().size,
      ),
    };
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) {
    // Not implemented - release verison must be specified by the user.
    throw UnimplementedError(
      'Release version must be specified using --release-version.',
    );
  }

  @override
  Future<CreatePatchMetadata> createPatchMetadata(DiffStatus diffStatus) async {
    return CreatePatchMetadata(
      releasePlatform: releaseType.releasePlatform,
      usedIgnoreAssetChangesFlag: allowAssetDiffs,
      hasAssetChanges: diffStatus.hasAssetChanges,
      usedIgnoreNativeChangesFlag: allowNativeDiffs,
      hasNativeChanges: diffStatus.hasNativeChanges,
      linkPercentage: lastBuildLinkPercentage,
      environment: BuildEnvironmentMetadata(
        operatingSystem: platform.operatingSystem,
        operatingSystemVersion: platform.operatingSystemVersion,
        shorebirdVersion: packageVersion,
        xcodeVersion: await xcodeBuild.version(),
      ),
    );
  }
}

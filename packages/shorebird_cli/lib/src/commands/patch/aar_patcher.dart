import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:io/io.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template aar_patcher}
/// Functions to patch an AAR release.
/// {@endtemplate}
class AarPatcher extends Patcher {
  /// {@macro aar_patcher}
  AarPatcher({
    required super.argResults,
    required super.argParser,
    required super.flavor,
    required super.target,
  });

  /// The build number of the aar (1.0). Forwarded to the --build-number
  /// argument of the flutter build aar command.
  String get buildNumber => argResults['build-number'] as String;

  @override
  String get primaryReleaseArtifactArch => 'aar';

  @override
  ReleaseType get releaseType => ReleaseType.aar;

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
      );
    } on PreconditionFailedException catch (e) {
      throw ProcessExit(e.exitCode.code);
    }

    if (shorebirdEnv.androidPackageName == null) {
      logger.err('Could not find androidPackage in pubspec.yaml.');
      throw ProcessExit(ExitCode.config.code);
    }
  }

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) =>
      patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
        localArchive: patchArchive,
        releaseArchive: releaseArchive,
        archiveDiffer: const AndroidArchiveDiffer(),
        allowAssetChanges: allowAssetDiffs,
        allowNativeChanges: allowNativeDiffs,
      );

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();
    final buildProgress =
        logger.progress('Building patch with Flutter $flutterVersionString');

    try {
      await artifactBuilder.buildAar(
        buildNumber: buildNumber,
        args: argResults.forwardedArgs,
      );
      buildProgress.complete();
    } on ArtifactBuildException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      throw ProcessExit(ExitCode.software.code);
    }

    return File(
      ShorebirdAndroidArtifacts.aarArtifactPath(
        buildNumber: buildNumber,
        packageName: shorebirdEnv.androidPackageName!,
      ),
    );
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
    File? supplementArtifact,
  }) async {
    final releaseArtifacts = await codePushClientWrapper.getReleaseArtifacts(
      appId: appId,
      releaseId: releaseId,
      architectures: AndroidArch.availableAndroidArchs,
      platform: releaseType.releasePlatform,
    );

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
      } on Exception catch (error) {
        downloadReleaseArtifactProgress.fail('$error');
        throw ProcessExit(ExitCode.software.code);
      }
    }

    downloadReleaseArtifactProgress.complete();

    final extractedAarDirectory = await shorebirdAndroidArtifacts.extractAar(
      packageName: shorebirdEnv.androidPackageName!,
      buildNumber: buildNumber,
      unzipFn: extractFileToDisk,
    );
    final patchArtifactBundles = <Arch, PatchArtifactBundle>{};

    final createDiffProgress = logger.progress('Creating artifacts');
    for (final releaseArtifactPath in releaseArtifactPaths.entries) {
      final arch = releaseArtifactPath.key;
      final artifactPath = p.join(
        extractedAarDirectory.path,
        'jni',
        arch.androidBuildPath,
        'libapp.so',
      );
      logger.detail('Creating artifact for $artifactPath');
      final patchArtifact = File(artifactPath);
      final hash = sha256.convert(await patchArtifact.readAsBytes()).toString();
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
      } on Exception catch (error) {
        createDiffProgress.fail('$error');
        throw ProcessExit(ExitCode.software.code);
      }
    }
    createDiffProgress.complete();

    return patchArtifactBundles;
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) {
    // Not implemented - release version must be specified by the user.
    throw UnimplementedError(
      'Release version must be specified using --release-version.',
    );
  }
}

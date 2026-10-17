import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/archive/directory_archive.dart';
import 'package:shorebird_cli/src/archive_analysis/apple_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/apple_patcher_mixin.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/extensions/directory.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template ios_framework_patcher}
/// Functions to patch an iOS Framework release.
/// {@endtemplate}
class IosFrameworkPatcher extends Patcher
    with ApplePatcherMixin, AppleLinkerPatcherMixin {
  /// {@macro ios_framework_patcher}
  IosFrameworkPatcher({
    required super.argResults,
    required super.argParser,
    required super.flavor,
    required super.target,
  });

  @override
  String get primaryReleaseArtifactArch => 'xcframework';

  @override
  String? get supplementaryReleaseArtifactArch => 'ios_framework_supplement';

  @override
  ReleaseType get releaseType => ReleaseType.iosFramework;

  @override
  Version? get minimumFlutterVersion => minimumSupportedIosFlutterVersion;

  @override
  List<Validator> get applePlatformValidators => doctor.iosCommandValidators;

  @override
  bool get requiresReleaseVersionArg => true;

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
    localArchive: patchArchive,
    releaseArchive: releaseArchive,
    archiveDiffer: const AppleArchiveDiffer(),
    allowAssetChanges: allowAssetDiffs,
    allowNativeChanges: allowNativeDiffs,
  );

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    final buildArgs = [...argResults.forwardedArgs, ...extraBuildArgs];
    final buildResult = await artifactBuilder.buildIosFramework(
      target: target,
      args: buildArgs,
      base64PublicKey: await getEncodedPublicKey(),
    );

    await buildAppleElfAotSnapshot(
      appDillPath: buildResult.kernelFile.path,
      outFilePath: aotOutputPath,
      genSnapshotArtifact: ShorebirdArtifact.genSnapshotIos,
    );

    // Copy the kernel file to the build directory so that it can be used
    // to generate a patch.
    buildResult.kernelFile.copySync(appDillCopyPath);

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
    required File releaseArtifact,
    Directory? supplementDirectory,
  }) async {
    final unzipProgress = logger.progress('Extracting release artifact');
    final releaseXcframeworkDirectory = Directory.systemTemp.createTempSync();
    // Only a supplement directory created here is ours to delete; one passed
    // in belongs to the caller.
    final fallbackSupplementDirectory = supplementDirectory == null
        ? Directory.systemTemp.createTempSync()
        : null;
    try {
      await artifactManager.extractZip(
        zipFile: releaseArtifact,
        outputDirectory: releaseXcframeworkDirectory,
      );

      unzipProgress.complete();
      final releaseArtifactFile = File(
        p.join(
          releaseXcframeworkDirectory.path,
          'ios-arm64',
          'App.framework',
          'App',
        ),
      );

      // The returned bundles point at the diff or the patch build output,
      // never into the extracted release, so it can go once this returns.
      return await linkAndBundlePatch(
        releaseArtifactFile: releaseArtifactFile,
        releaseSupplementDir:
            supplementDirectory ?? fallbackSupplementDirectory!,
      );
    } finally {
      releaseXcframeworkDirectory.deleteTemporarySync();
      if (fallbackSupplementDirectory != null) {
        fallbackSupplementDirectory.deleteTemporarySync();
      }
    }
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) {
    // Not implemented - release version must be specified by the user.
    throw UnimplementedError(
      'Release version must be specified using --release-version.',
    );
  }
}

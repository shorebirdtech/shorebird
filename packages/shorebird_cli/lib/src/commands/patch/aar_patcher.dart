import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/build_preconditions.dart';
import 'package:shorebird_cli/src/commands/patch/android_patcher_mixin.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template aar_patcher}
/// Functions to patch an AAR release.
/// {@endtemplate}
class AarPatcher extends Patcher with AndroidPatcherMixin {
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
  String? get supplementaryReleaseArtifactArch => 'aar_supplement';

  @override
  ReleaseType get releaseType => ReleaseType.aar;

  @override
  bool get requiresReleaseVersionArg => true;

  @override
  Future<void> assertPreconditions() async {
    await assertBuildPreconditions();
    assertAndroidPackageNameConfigured();
  }

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
    localArchive: patchArchive,
    releaseArchive: releaseArchive,
    archiveDiffer: const AndroidArchiveDiffer(),
    allowAssetChanges: allowAssetDiffs,
    allowNativeChanges: allowNativeDiffs,
  );

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    final buildArgs = [...argResults.forwardedArgs, ...extraBuildArgs];
    await artifactBuilder.buildAar(
      buildNumber: buildNumber,
      args: buildArgs,
      base64PublicKey: await getEncodedPublicKey(),
    );

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
    Directory? supplementDirectory,
    Duration downloadMessageTimeout = const Duration(minutes: 1),
  }) async {
    final releaseArtifactPaths = await downloadAndroidReleaseArtifacts(
      appId: appId,
      releaseId: releaseId,
      downloadMessageTimeout: downloadMessageTimeout,
    );

    final extractedAarDirectory = await shorebirdAndroidArtifacts.extractAar(
      packageName: shorebirdEnv.androidPackageName!,
      buildNumber: buildNumber,
      unzipFn: extractFileToDisk,
    );

    return createAndroidPatchArtifactBundles(
      releaseArtifactPaths: releaseArtifactPaths,
      patchArchsDir: Directory(p.join(extractedAarDirectory.path, 'jni')),
    );
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) {
    // Not implemented - release version must be specified by the user.
    throw UnimplementedError(
      'Release version must be specified using --release-version.',
    );
  }
}

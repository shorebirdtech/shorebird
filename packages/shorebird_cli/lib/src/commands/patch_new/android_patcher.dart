import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch_new/patcher.dart';
import 'package:shorebird_cli/src/commands/release_new/release_type.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template android_patcher}
/// Functions to create an Android patch.
/// {@endtemplate}
class AndroidPatcher extends Patcher {
  /// {@macro android_patcher}
  AndroidPatcher({required super.flavor, required super.target});

  @override
  ReleaseType get releaseType => ReleaseType.android;

  @override
  String get primaryReleaseArtifactArch => 'aab';

  @override
  ArchiveDiffer get archiveDiffer => AndroidArchiveDiffer();

  @override
  Future<void> assertArgsAreValid() async {
    // Nothing to do here
  }

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.androidCommandValidators,
      );
    } on PreconditionFailedException catch (e) {
      exit(e.exitCode.code);
    }
  }

  @override
  Future<File> buildPatchArtifact({
    required String? flavor,
    required String? target,
  }) async {
    final File aabFile;
    final buildProgress = logger.progress('Building patch');
    try {
      aabFile =
          await artifactBuilder.buildAppBundle(flavor: flavor, target: target);
      buildProgress.complete();
    } on ArtifactBuildException catch (error) {
      buildProgress.fail(error.message);
      exit(ExitCode.software.code);
    }

    final patchArchsBuildDir = ArtifactManager.androidArchsDirectory(
      projectRoot: projectRoot,
      flavor: flavor,
    );

    if (patchArchsBuildDir == null) {
      logger
        ..err('Cannot find patch build artifacts.')
        ..info(
          '''
Please run `shorebird cache clean` and try again. If the issue persists, please
file a bug report at https://github.com/shorebirdtech/shorebird/issues/new.

Looked in:
  - build/app/intermediates/stripped_native_libs/stripReleaseDebugSymbols/release/out/lib
  - build/app/intermediates/stripped_native_libs/strip{flavor}ReleaseDebugSymbols/{flavor}Release/out/lib
  - build/app/intermediates/stripped_native_libs/release/out/lib
  - build/app/intermediates/stripped_native_libs/{flavor}Release/out/lib''',
        );
    }
    return aabFile;
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
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
      } catch (error) {
        downloadReleaseArtifactProgress.fail('$error');
        exit(ExitCode.software.code);
      }
    }

    final patchArchsBuildDir = ArtifactManager.androidArchsDirectory(
      projectRoot: projectRoot,
      flavor: flavor,
    );
    if (patchArchsBuildDir == null) {
      logger.err('Could not find patch artifacts');
      exit(ExitCode.software.code);
    }

    final patchArtifactBundles = <Arch, PatchArtifactBundle>{};
    final createDiffProgress = logger.progress('Creating artifacts');
    for (final releaseArtifactPath in releaseArtifactPaths.entries) {
      final arch = releaseArtifactPath.key;
      final patchArtifactPath = p.join(
        patchArchsBuildDir.path,
        arch.androidBuildPath,
        'libapp.so',
      );
      logger.detail('Creating artifact for $patchArtifactPath');
      final patchArtifact = File(patchArtifactPath);
      final hash = sha256.convert(await patchArtifact.readAsBytes()).toString();
      try {
        final diffPath = await artifactManager.createDiff(
          releaseArtifactPath: releaseArtifactPath.value,
          patchArtifactPath: patchArtifactPath,
        );
        patchArtifactBundles[releaseArtifactPath.key] = PatchArtifactBundle(
          arch: arch.arch,
          path: diffPath,
          hash: hash,
          size: await File(diffPath).length(),
        );
      } catch (error) {
        createDiffProgress.fail('$error');
        exit(ExitCode.software.code);
      }
    }
    createDiffProgress.complete();
    return patchArtifactBundles;
  }

  @override
  Future<String> buildAppAndGetReleaseVersion() async {
    final builtApp = await buildPatchArtifact(flavor: flavor, target: target);
    try {
      return await shorebirdAndroidArtifacts.extractReleaseVersionFromAppBundle(
        builtApp.path,
      );
    } catch (error) {
      logger.err('$error');
      exit(ExitCode.software.code);
    }
  }

  @override
  Future<File> patchArtifactForDiffCheck() async {
    return shorebirdAndroidArtifacts.findAab(
      project: projectRoot,
      flavor: flavor,
    );
  }
}

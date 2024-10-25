import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/patch/patcher.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template android_patcher}
/// Functions to create an Android patch.
/// {@endtemplate}
class AndroidPatcher extends Patcher {
  /// {@macro android_patcher}
  AndroidPatcher({
    required super.argResults,
    required super.argParser,
    required super.flavor,
    required super.target,
  });

  @override
  ReleaseType get releaseType => ReleaseType.android;

  @override
  String get primaryReleaseArtifactArch => 'aab';

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
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.androidCommandValidators,
      );
    } on PreconditionFailedException catch (e) {
      throw ProcessExit(e.exitCode.code);
    }
  }

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    final File aabFile;
    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();
    final buildProgress =
        logger.progress('Building patch with Flutter $flutterVersionString');

    try {
      aabFile = await artifactBuilder.buildAppBundle(
        flavor: flavor,
        target: target,
        args: argResults.forwardedArgs +
            buildNameAndNumberArgsFromReleaseVersion(releaseVersion),
        base64PublicKey: argResults.encodedPublicKey,
        baseProgressMessage:
            'Building patch with Flutter $flutterVersionString',
        buildProgress: buildProgress,
      );
      buildProgress.complete();
    } on ArtifactBuildException catch (error) {
      buildProgress.fail(error.message);
      throw ProcessExit(ExitCode.software.code);
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
      throw ProcessExit(ExitCode.software.code);
    }
    return aabFile;
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
  }) async {
    final releaseArtifacts = await codePushClientWrapper.getReleaseArtifacts(
      appId: appId,
      releaseId: releaseId,
      architectures: AndroidArch.availableAndroidArchs,
      platform: releaseType.releasePlatform,
    );
    final releaseArtifactPaths = <Arch, String>{};
    final numArtifacts = releaseArtifacts.length;

    for (final (i, releaseArtifact) in releaseArtifacts.entries.indexed) {
      try {
        final releaseArtifactFile =
            await artifactManager.downloadWithProgressUpdates(
          Uri.parse(releaseArtifact.value.url),
          message: 'Downloading release artifact ${i + 1}/$numArtifacts',
        );
        releaseArtifactPaths[releaseArtifact.key] = releaseArtifactFile.path;
      } catch (error) {
        throw ProcessExit(ExitCode.software.code);
      }
    }

    final patchArchsBuildDir = ArtifactManager.androidArchsDirectory(
      projectRoot: projectRoot,
      flavor: flavor,
    );
    if (patchArchsBuildDir == null) {
      logger.err('Could not find patch artifacts');
      throw ProcessExit(ExitCode.software.code);
    }

    final patchArtifactBundles = <Arch, PatchArtifactBundle>{};
    final createDiffProgress = logger.progress('Creating patch artifacts');
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

      final privateKeyFile = argResults.file(
        CommonArguments.privateKeyArg.name,
      );
      final hashSignature = privateKeyFile != null
          ? codeSigner.sign(
              message: hash,
              privateKeyPemFile: privateKeyFile,
            )
          : null;

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
          hashSignature: hashSignature,
        );
      } catch (error) {
        createDiffProgress.fail('$error');
        throw ProcessExit(ExitCode.software.code);
      }
    }
    createDiffProgress.complete();
    return patchArtifactBundles;
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) async {
    return shorebirdAndroidArtifacts.extractReleaseVersionFromAppBundle(
      artifact.path,
    );
  }
}

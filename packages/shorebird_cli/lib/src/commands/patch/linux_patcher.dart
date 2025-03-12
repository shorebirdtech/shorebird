import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive/archive.dart';
import 'package:shorebird_cli/src/archive_analysis/linux_bundle_differ.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template linux_patcher}
/// Functions to create a linux patch.
/// {@endtemplate}
class LinuxPatcher extends Patcher {
  /// {@macro linux_patcher}
  LinuxPatcher({
    required super.argParser,
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  @override
  Future<void> assertPreconditions() async {}

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) async {
    return patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
      localArchive: patchArchive,
      releaseArchive: releaseArchive,
      archiveDiffer: const LinuxBundleDiffer(),
      allowAssetChanges: allowAssetDiffs,
      allowNativeChanges: allowNativeDiffs,
    );
  }

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    await artifactBuilder.buildLinuxApp(
      base64PublicKey: argResults.encodedPublicKey,
    );
    return artifactManager.linuxBundleDirectory.zipToTempFile();
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
    File? supplementArtifact,
  }) async {
    final createDiffProgress = logger.progress('Creating patch artifacts');
    final patchArtifactPath = p.join(
      artifactManager.linuxBundleDirectory.path,
      'lib',
      'libapp.so',
    );
    final patchArtifact = File(patchArtifactPath);
    final hash = sha256.convert(await patchArtifact.readAsBytes()).toString();

    final tempDir = Directory.systemTemp.createTempSync();
    final zipPath = p.join(tempDir.path, 'patch.zip');
    final zipFile = releaseArtifact.copySync(zipPath);
    await artifactManager.extractZip(
      zipFile: zipFile,
      outputDirectory: tempDir,
    );

    // The release artifact is the zipped directory at
    // build/linux/x64/release/bundle
    final appSoPath = p.join(tempDir.path, 'lib', 'libapp.so');

    final privateKeyFile = argResults.file(CommonArguments.privateKeyArg.name);
    final hashSignature =
        privateKeyFile != null
            ? codeSigner.sign(message: hash, privateKeyPemFile: privateKeyFile)
            : null;

    final String diffPath;
    try {
      diffPath = await artifactManager.createDiff(
        releaseArtifactPath: appSoPath,
        patchArtifactPath: patchArtifactPath,
      );
    } on Exception catch (error) {
      createDiffProgress.fail('$error');
      throw ProcessExit(ExitCode.software.code);
    }

    createDiffProgress.complete();

    return {
      Arch.x86_64: PatchArtifactBundle(
        arch: Arch.x86_64.arch,
        path: diffPath,
        hash: hash,
        size: File(diffPath).lengthSync(),
        hashSignature: hashSignature,
      ),
    };
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) async {
    final outputDirectory = Directory.systemTemp.createTempSync();
    await artifactManager.extractZip(
      zipFile: artifact,
      outputDirectory: outputDirectory,
    );
    return linux.versionFromLinuxBundle(bundleRoot: outputDirectory);
  }

  @override
  String get primaryReleaseArtifactArch => 'bundle';

  @override
  ReleaseType get releaseType => ReleaseType.linux;
}

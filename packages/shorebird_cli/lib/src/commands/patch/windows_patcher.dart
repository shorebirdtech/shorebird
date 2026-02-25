import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive/archive.dart';
import 'package:shorebird_cli/src/archive_analysis/windows_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patcher.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template windows_patcher}
/// Functions to create a Windows patch.
/// {@endtemplate}
class WindowsPatcher extends Patcher {
  /// {@macro windows_patcher}
  WindowsPatcher({
    required super.argParser,
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  @override
  String get primaryReleaseArtifactArch => primaryWindowsReleaseArtifactArch;

  @override
  ReleaseType get releaseType => ReleaseType.windows;

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.windowsCommandValidators,
        supportedOperatingSystems: {Platform.windows},
      );
    } on PreconditionFailedException catch (e) {
      throw ProcessExit(e.exitCode.code);
    }
  }

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) {
    return patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
      localArchive: patchArchive,
      releaseArchive: releaseArchive,
      archiveDiffer: const WindowsArchiveDiffer(),
      allowAssetChanges: allowAssetDiffs,
      allowNativeChanges: allowNativeDiffs,
    );
  }

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    final buildArgs = [...argResults.forwardedArgs];
    if (argResults['obfuscate'] == true &&
        !buildArgs.any((a) => a.startsWith('--split-debug-info'))) {
      buildArgs.add(
        '--split-debug-info=${p.join('build', 'shorebird', 'symbols')}',
      );
    }
    final releaseDir = await artifactBuilder.buildWindowsApp(
      target: target,
      args: buildArgs,
      base64PublicKey: argResults.encodedPublicKey,
    );
    return releaseDir.zipToTempFile();
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
      artifactManager.getWindowsReleaseDirectory().path,
      'data',
      'app.so',
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
    // build/windows/x64/runner/Release
    final appSoPath = p.join(tempDir.path, 'data', 'app.so');

    final hashSignature = await signHash(hash);

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
    final executable = windows.findExecutable(
      releaseDirectory: outputDirectory,
      projectName: shorebirdEnv.getPubspecYaml()!.name,
    );
    return powershell.getProductVersion(executable);
  }
}

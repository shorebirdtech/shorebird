import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive/archive.dart';
import 'package:shorebird_cli/src/archive_analysis/windows_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patcher.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
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
  // TODO(bryanoltman): exe isn't technically correct - we upload a zip
  // containing the exe along with dlls and assets. We should find a better name
  // for this.
  String get primaryReleaseArtifactArch => 'exe';

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
  Future<File> buildPatchArtifact({
    String? releaseVersion,
  }) async {
    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();

    final buildAppBundleProgress = logger.detailProgress(
      'Building Windows app with Flutter $flutterVersionString',
    );

    final Directory releaseDir;
    try {
      releaseDir = await artifactBuilder.buildWindowsApp();
      buildAppBundleProgress.complete();
    } on Exception catch (e) {
      buildAppBundleProgress.fail(e.toString());
      throw ProcessExit(ExitCode.software.code);
    }

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
      projectRoot.path,
      'build',
      'windows',
      'x64',
      'runner',
      'Release',
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
    final exeFile = outputDirectory
        .listSync()
        .whereType<File>()
        .firstWhere((file) => p.extension(file.path) == '.exe');
    return powershell.getExeVersionString(exeFile);
  }
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive/archive.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/build_preconditions.dart';
import 'package:shorebird_cli/src/commands/patch/patcher.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template desktop_patcher}
/// Creates patches for desktop platforms whose release artifact is a zip of
/// the built app directory containing a single x86_64 Dart library (Linux and
/// Windows).
///
/// Subclasses supply only what differs per platform: how to build the app,
/// where the build puts it, where the Dart library sits inside it, and how to
/// read the version back out of a release.
///
/// macOS is not a [DesktopPatcher]; see `MacosPatcher` for why.
/// {@endtemplate}
abstract class DesktopPatcher extends Patcher {
  /// {@macro desktop_patcher}
  DesktopPatcher({
    required super.argParser,
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  /// The doctor validators to run before patching.
  List<Validator> get commandValidators;

  /// The operating system patches for this platform must be built on.
  String get hostOperatingSystem;

  /// Compares a release archive with a patch archive.
  ArchiveDiffer get archiveDiffer;

  /// The directory the build writes the app to.
  Directory get appDirectory;

  /// The path of the Dart library relative to [appDirectory], which is also
  /// its path inside the zipped release artifact.
  List<String> get dartLibraryPathSegments;

  /// Builds the app with [args] and returns the directory to zip as the patch
  /// archive.
  Future<Directory> buildApp({
    required List<String> args,
    String? base64PublicKey,
  });

  /// Reads the release version from an extracted release artifact.
  Future<String> versionFromAppDirectory(Directory appDirectory);

  @override
  Future<void> assertPreconditions() => assertBuildPreconditions(
    validators: commandValidators,
    supportedOperatingSystems: {hostOperatingSystem},
  );

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) {
    return patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
      localArchive: patchArchive,
      releaseArchive: releaseArchive,
      archiveDiffer: archiveDiffer,
      allowAssetChanges: allowAssetDiffs,
      allowNativeChanges: allowNativeDiffs,
    );
  }

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    final buildArgs = [...argResults.forwardedArgs, ...extraBuildArgs];
    final builtDirectory = await buildApp(
      args: buildArgs,
      base64PublicKey: await getEncodedPublicKey(),
    );
    return builtDirectory.zipToTempFile();
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
    Directory? supplementDirectory,
  }) async {
    final createDiffProgress = logger.progress('Creating patch artifacts');
    final patchArtifactPath = p.joinAll([
      appDirectory.path,
      ...dartLibraryPathSegments,
    ]);
    final tempDir = Directory.systemTemp.createTempSync();
    final zipPath = p.join(tempDir.path, 'patch.zip');
    final zipFile = releaseArtifact.copySync(zipPath);
    await artifactManager.extractZip(
      zipFile: zipFile,
      outputDirectory: tempDir,
    );

    final bundle = await createDiffBundle(
      arch: Arch.x86_64,
      releaseArtifactPath: p.joinAll([
        tempDir.path,
        ...dartLibraryPathSegments,
      ]),
      patchArtifactPath: patchArtifactPath,
      progress: createDiffProgress,
    );
    createDiffProgress.complete();

    return {Arch.x86_64: bundle};
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) async {
    final outputDirectory = Directory.systemTemp.createTempSync();
    await artifactManager.extractZip(
      zipFile: artifact,
      outputDirectory: outputDirectory,
    );
    return versionFromAppDirectory(outputDirectory);
  }
}

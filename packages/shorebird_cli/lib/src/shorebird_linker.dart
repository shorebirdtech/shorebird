import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/executables/aot_tools.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// A reference to a [ShorebirdLinker] instance.
final shorebirdLinkerRef = create(ShorebirdLinker.new);

/// The [ShorebirdLinker] instance available in the current zone.
ShorebirdLinker get shorebirdLinker => read(shorebirdLinkerRef);

/// {@template link_result}
/// The result of linking a patch artifact.
/// {@endtemplate}
class LinkResult {
  /// {@macro link_result}
  const LinkResult({
    required this.patchBuildFile,
    required this.linkPercentage,
  });

  /// The linked patch build file.
  final File patchBuildFile;

  /// The link percentage, if reported.
  final double? linkPercentage;
}

/// {@template shorebird_linker}
/// Functions to link AOT files.
/// {@endtemplate}
class ShorebirdLinker {
  String get _buildDirectory => p.join(
        shorebirdEnv.getShorebirdProjectRoot()!.path,
        'build',
      );

  String get _vmcodeOutputPath => p.join(
        _buildDirectory,
        'out.vmcode',
      );

  /// Uses the aot_tools executable to link the release and patch artifacts, if
  /// supported by the Flutter revision reported by [ShorebirdEnv].
  Future<LinkResult> linkPatchArtifactIfPossible({
    required File releaseArtifact,
    required File patchBuildFile,
  }) async {
    if (!AotTools.usesLinker(shorebirdEnv.flutterRevision)) {
      // If the linker is not used for the current Flutter revision, there is
      // nothing for us to do.
      return LinkResult(
        patchBuildFile: patchBuildFile,
        linkPercentage: null,
      );
    }

    final analyzeSnapshot = File(
      shorebirdArtifacts.getArtifactPath(
        artifact: ShorebirdArtifact.analyzeSnapshot,
      ),
    );

    final genSnapshot = shorebirdArtifacts.getArtifactPath(
      artifact: ShorebirdArtifact.genSnapshot,
    );

    // final linkProgress = logger.progress('Linking AOT files');
    final double? linkPercentage;
    try {
      linkPercentage = await aotTools.link(
        base: releaseArtifact.path,
        patch: patchBuildFile.path,
        analyzeSnapshot: analyzeSnapshot.path,
        genSnapshot: genSnapshot,
        kernel: artifactManager.newestAppDill().path,
        outputPath: _vmcodeOutputPath,
        workingDirectory: _buildDirectory,
      );
    } catch (error) {
      // linkProgress.fail('Failed to link AOT files: $error');
      exit(ExitCode.software.code);
    }

    // linkProgress.complete();

    if (!await aotTools.isGeneratePatchDiffBaseSupported()) {
      return LinkResult(
        patchBuildFile: File(_vmcodeOutputPath),
        linkPercentage: linkPercentage,
      );
    }

    // If the aot_tools executable supports the dump_blobs command, we
    // can generate a stable diff base and use that to create a patch.
    final patchBaseFile = await aotTools.generatePatchDiffBase(
      analyzeSnapshotPath: analyzeSnapshot.path,
      releaseSnapshot: releaseArtifact,
    );
    final patchFile = File(
      await artifactManager.createDiff(
        releaseArtifactPath: patchBaseFile.path,
        patchArtifactPath: patchBuildFile.path,
      ),
    );

    return LinkResult(
      patchBuildFile: patchFile,
      linkPercentage: linkPercentage,
    );
  }
}

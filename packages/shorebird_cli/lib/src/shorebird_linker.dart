import 'dart:io';

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

/// {@template link_failure_exception}
/// An exception thrown when linking fails.
/// {@endtemplate}
class LinkFailureException implements Exception {
  /// {@macro link_failure_exception}
  const LinkFailureException(this.message);

  /// The message describing the failure.
  final String message;

  @override
  String toString() => 'LinkFailureException: $message';
}

/// {@template shorebird_linker}
/// Functions to link AOT files.
/// {@endtemplate}
class ShorebirdLinker {
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

    final double? linkPercentage;
    final buildDirectory = Directory(
      p.join(
        shorebirdEnv.getShorebirdProjectRoot()!.path,
        'build',
      ),
    );
    final vmcodeFile = File(
      p.join(buildDirectory.path, 'out.vmcode'),
    );

    try {
      linkPercentage = await aotTools.link(
        base: releaseArtifact.path,
        patch: patchBuildFile.path,
        analyzeSnapshot: analyzeSnapshot.path,
        genSnapshot: genSnapshot,
        kernel: artifactManager.newestAppDill().path,
        outputPath: vmcodeFile.path,
        workingDirectory: buildDirectory.path,
      );
    } catch (error) {
      throw LinkFailureException('$error');
    }

    if (!await aotTools.isGeneratePatchDiffBaseSupported()) {
      return LinkResult(
        patchBuildFile: vmcodeFile,
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

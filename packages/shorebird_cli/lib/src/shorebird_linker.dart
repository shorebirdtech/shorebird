import 'dart:io';

import 'package:crypto/crypto.dart';
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
    required this.patchHash,
    required this.linkPercentage,
  });

  /// The linked patch build file.
  final File patchBuildFile;

  /// The hash of full (non-diff) patch file.
  final String patchHash;

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
    required File patchSnapshotFile,
  }) async {
    final File maybeLinkedFile;
    final double? linkPercentage;

    if (AotTools.usesLinker(shorebirdEnv.flutterRevision)) {
      final analyzeSnapshot = File(
        shorebirdArtifacts.getArtifactPath(
          artifact: ShorebirdArtifact.analyzeSnapshot,
        ),
      );
      final genSnapshot = shorebirdArtifacts.getArtifactPath(
        artifact: ShorebirdArtifact.genSnapshot,
      );

      final buildDirectory = Directory(
        p.join(
          shorebirdEnv.getShorebirdProjectRoot()!.path,
          'build',
        ),
      );

      maybeLinkedFile = File(
        p.join(buildDirectory.path, 'out.vmcode'),
      );
      try {
        linkPercentage = await aotTools.link(
          base: releaseArtifact.path,
          patch: patchSnapshotFile.path,
          analyzeSnapshot: analyzeSnapshot.path,
          genSnapshot: genSnapshot,
          kernel: artifactManager.newestAppDill().path,
          outputPath: maybeLinkedFile.path,
          workingDirectory: buildDirectory.path,
        );
      } catch (error) {
        throw LinkFailureException('$error');
      }
    } else {
      maybeLinkedFile = patchSnapshotFile;
      linkPercentage = null;
    }

    if (!await aotTools.isGeneratePatchDiffBaseSupported()) {
      return LinkResult(
        patchBuildFile: maybeLinkedFile,
        patchHash: sha256.convert(maybeLinkedFile.readAsBytesSync()).toString(),
        linkPercentage: linkPercentage,
      );
    }

    final analyzeSnapshot = File(
      shorebirdArtifacts.getArtifactPath(
        artifact: ShorebirdArtifact.analyzeSnapshot,
      ),
    );

    // If the aot_tools executable supports the dump_blobs command, we
    // can generate a stable diff base and use that to create a patch.
    final patchBaseFile = await aotTools.generatePatchDiffBase(
      analyzeSnapshotPath: analyzeSnapshot.path,
      releaseSnapshot: releaseArtifact,
    );
    final patchFile = File(
      await artifactManager.createDiff(
        releaseArtifactPath: patchBaseFile.path,
        patchArtifactPath: maybeLinkedFile.path,
      ),
    );

    return LinkResult(
      patchBuildFile: patchFile,
      patchHash: sha256.convert(maybeLinkedFile.readAsBytesSync()).toString(),
      linkPercentage: linkPercentage,
    );
  }
}

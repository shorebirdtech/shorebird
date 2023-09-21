import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/process.dart';

/// A reference to a [ArtifactDiffGenerator] instance.
final artifactDiffGeneratorRef = create(ArtifactDiffGenerator.new);

/// The [ArtifactDiffGenerator] instance available in the current zone.
ArtifactDiffGenerator get artifactDiffGenerator =>
    read(artifactDiffGeneratorRef);

/// {@template artifact_differ}
/// A class for creating binary diffs between two files.
/// {@endtemplate}
class ArtifactDiffGenerator {
  /// Generates a binary diff between two files and returns the path to the
  /// output diff file.
  Future<String> createDiff({
    required String releaseArtifactPath,
    required String patchArtifactPath,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp();
    final diffPath = p.join(tempDir.path, 'diff.patch');
    final diffExecutable = p.join(
      cache.getArtifactDirectory('patch').path,
      'patch',
    );
    final diffArguments = [
      releaseArtifactPath,
      patchArtifactPath,
      diffPath,
    ];

    final result = await process.run(diffExecutable, diffArguments);

    if (result.exitCode != 0) {
      throw Exception('Failed to create diff: ${result.stderr}');
    }

    return diffPath;
  }
}

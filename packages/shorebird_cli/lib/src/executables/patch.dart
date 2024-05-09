import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// A reference to a [PatchProgram] instance.
final patchProgramRef = create(PatchProgram.new);

/// The [PatchProgram] instance available in the current zone.
PatchProgram get patchProgram => read(patchProgramRef);

/// {@template patch_failed_exception}
/// An exception thrown when a patch fails.
/// {@endtemplate}
class PatchFailedException implements Exception {
  /// {@macro patch_failed_exception}
  PatchFailedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A wrapper around the `patch` executable.
///
/// Used to create diffs between files.
///
/// Throws [PatchFailedException] if the patch command exits with non-zero code.
class PatchProgram {
  Future<void> run({
    required String releaseArtifactPath,
    required String patchArtifactPath,
    required String diffPath,
  }) async {
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

    if (result.exitCode != ExitCode.success.code) {
      throw PatchFailedException(
        '''
Failed to create diff (exit code ${result.exitCode}).
  stdout: ${result.stdout}
  stderr: ${result.stderr}''',
      );
    }
  }
}

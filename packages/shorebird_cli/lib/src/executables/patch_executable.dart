import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// A reference to a [PatchExecutable] instance.
final patchExecutableRef = create(PatchExecutable.new);

/// The [PatchExecutable] instance available in the current zone.
PatchExecutable get patchExecutable => read(patchExecutableRef);

/// {@template patch_failed_exception}
/// An exception thrown when a patch fails.
/// {@endtemplate}
class PatchFailedException implements Exception {
  /// {@macro patch_failed_exception}
  PatchFailedException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => message;
}

/// A wrapper around the `patch` executable.
///
/// Used to create diffs between files.
///
/// Throws [PatchFailedException] if the patch command exits with non-zero code.
class PatchExecutable {
  /// Runs the `patch` executable.
  Future<void> run({
    required String releaseArtifactPath,
    required String patchArtifactPath,
    required String diffPath,
  }) async {
    final diffExecutable = p.join(
      cache.getArtifactDirectory('patch').path,
      'patch',
    );
    final diffArguments = [releaseArtifactPath, patchArtifactPath, diffPath];

    final result = await process.run(
      diffExecutable,
      diffArguments,
      // Never run in shell because we always have a fully resolved
      // executable path.
      runInShell: false,
    );

    var messageDetails = '';

    // A Windows-specific error code indicating that the Microsoft C++ runtime
    // (VCRUNTIME140.dll) could not be found.
    // More info: https://github.com/shorebirdtech/shorebird/issues/2329
    const vcRuntimeNotFoundExitCode = -1073741515;
    if (result.exitCode == vcRuntimeNotFoundExitCode && platform.isWindows) {
      messageDetails =
          '''
This error code indicates that the Microsoft C++ runtime (VCRUNTIME140.dll) could not be found.

The C++ Runtime can be installed from Microsoft at:
${link(uri: Uri.parse('https://www.microsoft.com/en-us/download/details.aspx?id=52685'))}

Please try again once you have installed this software.
''';
    }

    if (result.exitCode != ExitCode.success.code) {
      throw PatchFailedException('''
Failed to create diff (exit code ${result.exitCode}). $messageDetails
  stdout: ${result.stdout}
  stderr: ${result.stderr}''');
    }
  }
}

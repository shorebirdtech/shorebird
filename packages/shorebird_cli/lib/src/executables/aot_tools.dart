import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/process.dart';

/// Wrapper around the shorebird `aot-tools` executable.
class AotTools {
  static const executableName = 'aot-tools';

  Future<ShorebirdProcessResult> _exec(
    List<String> command, {
    String? workingDirectory,
  }) async {
    await cache.updateAll();
    final executable = p.join(
      cache.getArtifactDirectory(executableName).path,
      executableName,
    );

    return process.run(executable, command, workingDirectory: workingDirectory);
  }

  /// Generate a link vmcode file from two AOT snapshots.
  Future<void> link({
    required String base,
    required String patch,
    required String analyzeSnapshot,
    String? workingDirectory,
  }) async {
    final result = await _exec(
      [
        'link',
        '--base=$base',
        '--patch=$patch',
        '--analyze-snapshot=$analyzeSnapshot',
      ],
      workingDirectory: workingDirectory,
    );

    if (result.exitCode != 0) {
      throw Exception('Failed to link: ${result.stderr}');
    }
  }
}

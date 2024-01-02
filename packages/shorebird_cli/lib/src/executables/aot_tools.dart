import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// A reference to a [AotTools] instance.
final aotToolsRef = create(AotTools.new);

/// The [AotTools] instance available in the current zone.
AotTools get aotTools => read(aotToolsRef);

/// Wrapper around the shorebird `aot-tools` executable.
class AotTools {
  Future<ShorebirdProcessResult> _exec(
    List<String> command, {
    String? workingDirectory,
  }) async {
    await cache.updateAll();

    // This will be a path to either a kernel (.dill) file or a Dart script if
    // we're running with a local engine.
    final artifactPath = shorebirdArtifacts.getArtifactPath(
      artifact: ShorebirdArtifact.aotTools,
    );

    return process.run(
      shorebirdEnv.dartBinaryFile.path,
      [artifactPath, ...command],
      workingDirectory: workingDirectory,
    );
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

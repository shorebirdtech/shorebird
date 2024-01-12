import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

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
    required String outputPath,
    String? workingDirectory,
  }) async {
    final result = await _exec(
      [
        'link',
        '--base=$base',
        '--patch=$patch',
        '--analyze-snapshot=$analyzeSnapshot',
        '--output=$outputPath',
      ],
      workingDirectory: workingDirectory,
    );

    if (result.exitCode != 0) {
      throw Exception('Failed to link: ${result.stderr}');
    }
  }

  /// Whether the current analyze_snapshot executable supports the
  /// `--dump-blobs` flag.
  Future<bool> isGeneratePatchDiffBaseSupported() async {
    // This will always return a non-zero exit code because the input is a
    // (presumably) nonexistent file. If the --dump-blobs flag is supported,
    // the error message will contain something like: "Snapshot file does not
    // exist". If the flag is not supported, the error message will contain
    // "Unrecognized flags: dump_blobs"
    final result = await _exec(
      [
        'dump_blobs',
        '--analyze-snapshot=nonexistent_analzye_snapshot',
        '--output=out',
        '--snapshot=nonexistent_snapshot',
      ],
    );
    return !result.stderr
        .toString()
        .contains('Could not find a command named "dump_blobs"');
  }

  /// Uses the analyze_snapshot executable to write the data and isolate
  /// snapshots contained in [releaseSnapshot]. Returns the generated diff base
  /// file.
  Future<File> generatePatchDiffBase({
    required File releaseSnapshot,
    required String analyzeSnapshotPath,
  }) async {
    final tmpDir = Directory.systemTemp.createTempSync();
    final outFile = File(p.join(tmpDir.path, 'diff_base'));
    final result = await _exec(
      [
        'dump_blobs',
        '--analyze-snapshot=$analyzeSnapshotPath',
        '--output=${outFile.path}',
        '--snapshot=${releaseSnapshot.path}',
      ],
    );

    if (result.exitCode != ExitCode.success.code) {
      throw Exception('Failed to generate patch diff base: ${result.stderr}');
    }

    if (!outFile.existsSync()) {
      throw Exception(
        'Failed to generate patch diff base: output file does not exist',
      );
    }

    return outFile;
  }
}

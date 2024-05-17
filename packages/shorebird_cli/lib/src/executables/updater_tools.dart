import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/patch_executable.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

/// A reference to a [UpdaterTools] instance.
final updaterToolsRef = create(UpdaterTools.new);

/// The [UpdaterTools] instance available in the current zone.
UpdaterTools get updaterTools => read(updaterToolsRef);

class UpdaterTools {
  /// Path to the updater tools .dill file.
  String get path => shorebirdArtifacts.getArtifactPath(
        artifact: ShorebirdArtifact.updaterTools,
      );

  Future<ShorebirdProcessResult> _exec(
    List<String> command, {
    String? workingDirectory,
  }) async {
    // local engine versions use .dart and we distribute aot-tools as a .dill
    return process.run(
      shorebirdEnv.dartBinaryFile.path,
      ['run', path, ...command],
      workingDirectory: workingDirectory,
    );
  }

  /// Create a binary diff between a release artifact and a patch artifact.
  Future<void> createDiff({
    required String releaseArtifactPath,
    required String patchArtifactPath,
    required String diffPath,
  }) async {
    if (!File(releaseArtifactPath).existsSync()) {
      throw FileSystemException(
        'Release artifact does not exist',
        releaseArtifactPath,
      );
    }

    if (!File(patchArtifactPath).existsSync()) {
      throw FileSystemException(
        'Patch artifact does not exist',
        patchArtifactPath,
      );
    }

    final result = await _exec([
      'diff',
      '--release=$releaseArtifactPath',
      '--patch=$patchArtifactPath',
      '--patch-executable=${patchExecutable.path}',
      '--output=$diffPath',
    ]);

    if (result.exitCode != ExitCode.success.code) {
      throw Exception('Failed to create diff: ${result.stderr}');
    }
  }
}

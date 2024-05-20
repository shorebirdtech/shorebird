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
    required File releaseArtifact,
    required File patchArtifact,
    required File outputFile,
  }) async {
    if (!releaseArtifact.existsSync()) {
      throw FileSystemException(
        'Release artifact does not exist',
        releaseArtifact.path,
      );
    }

    if (!patchArtifact.existsSync()) {
      throw FileSystemException(
        'Patch artifact does not exist',
        patchArtifact.path,
      );
    }

    final result = await _exec([
      'diff',
      '--release=${releaseArtifact.path}',
      '--patch=${patchArtifact.path}',
      '--patch-executable=${patchExecutable.path}',
      '--output=${outputFile.path}',
    ]);

    if (result.exitCode != ExitCode.success.code) {
      throw Exception('Failed to create diff: ${result.stderr}');
    }
  }
}

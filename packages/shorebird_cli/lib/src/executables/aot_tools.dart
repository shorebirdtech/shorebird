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

/// Revisions of Flutter that were released before the linker was enabled.
const preLinkerFlutterRevisions = <String>{
  '45d609090a2313d47a4e657d449ff25710abc853',
  '0b0086ffa92c25c22f50cbadc3851054f08a9cd8',
  'a3d5f7c614aa1cc4d6cb1506e74fd1c81678e68e',
  'b7ad8d5759c4889ea323948fe589c69a39c26135',
  '49b602f7fae8f5bcd8de9547f31928058cbd768e',
  '6116674ab0d6449104f9f342d96cef0abe30a9a1',
  'ba444de6ceb9313320a70563d7b6203344e0cd87',
  '0671f4f9fb2589055d64537e03d7733448b3488b',
  '1cf1fef6a503672b919a4390ed61320daac07139',
  '5de12cedfe6002b79183bc59af04561a98c8aa82',
  '9486b6431e6c808c4e131f134b5d88017b3c32ab',
  '2e05c41803943a1e81360ae97c75a229c1fb55ef',
  '0e2d280277cf9f60f7ba802a59f9fd187ffdd050',
  '628a3eba4e0aba5e6f92c87b320f3c99afb85e61',
  '3612c8dc659dd7866578b19396efcb63cad71bef',
  'd84d466eacbeb47d6e81e960c22c6fdfe5a3917d',
  '8576da53c568d904f464b8aeac105c8790285d32',
  'd93eb3686c60b626691c8020d7353ea22a0f5ea2',
  '39df2792f537b1fc62a9c668a6990f585bd91456',
  '03e895ee09dfbb9c18681d103f4b27671ff65429',
  'b9b23902966504a9778f4c07e3a3487fa84dcb2a',
  '02454bae6bf3bef150171c9ce299279e8b875b2e',
  '8861a600668dbc4d9ca131f5158871bc0523f428',
  'ef4b661ddc0c71b738432ae59c6bc573e917854b',
  '47db6d73cfe3227129a510445dd82c45c2dbe347',
  '7b63f1bac9879c2b00f02bc8d404ffc4c7f24ca2',
  '012153de178d4a51cd6f9adc792ad63ae3cfb1b3',
  '83305b5088e6fe327fb3334a73ff190828d85713',
  '225beb5302e2f03603a775d23be11d96ae253ab1',
  '402424409c29c28ed69e14cbb39f0a7424a47e16',
  'b27620fa7dca89c742c12b1277571f7a0d6a9740',
  '447487a4d2f1a73376e82c61e708f75e315cdaa5',
  'c0e52af9097e779671591ea105031920f24da4d5',
  '211d78f6d673fdc6f728217c8f999827c040cd23',
  'efce3391b9c729e2899e4e1383df718c4445c3ae',
  '0f62afa7ad2eaa2fa44ff28278d6c6eaf81f327e',
  '0fc414cbc33ee017ad509671009e8b242539ea16',
  '6b9b5ff45af7a1ef864038dd7d0c32b620b357c6',
  '7cd77f78a51576652edc337817152abf4217a257',
  '5567fb431a2ddbb70c05ff7cd8fcd58bb91f2dbc',
  '914d5b5fcacc794fd0319f2928ceb514e1e0da33',
  'e744c831b8355bcb9f3b541d42431d9145eea677',
  '1a6115bebe31e63508c312d14e69e973e1a59dbf',
};

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

    // Fallback behavior for older versions of shorebird where aot-tools was
    // distributed as an executable.
    final extension = p.extension(artifactPath);
    if (extension != '.dill' && extension != '.dart') {
      return process.run(
        artifactPath,
        command,
        workingDirectory: workingDirectory,
      );
    }

    // local engine versions use .dart and we distribute aot-tools as a .dill
    return process.run(
      shorebirdEnv.dartBinaryFile.path,
      ['run', artifactPath, ...command],
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
    final result = await _exec(['--help']);
    return result.stdout.toString().contains('dump_blobs');
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

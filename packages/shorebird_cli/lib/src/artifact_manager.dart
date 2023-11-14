import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/process.dart';

/// A reference to a [ArtifactManager] instance.
final artifactManagerRef = create(ArtifactManager.new);

/// The [ArtifactManager] instance available in the current zone.
ArtifactManager get artifactManager => read(artifactManagerRef);

class ArtifactManager {
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
      throw Exception(
        '''
Failed to create diff (exit code ${result.exitCode}).
  stdout: ${result.stdout}
  stderr: ${result.stderr}''',
      );
    }

    return diffPath;
  }

  /// Downloads the file at the given [uri] to a temporary directory and returns
  /// the path to the downloaded file.
  Future<String> downloadFile(
    Uri uri, {
    required http.Client httpClient,
    String? outputPath,
  }) async {
    final request = http.Request('GET', uri);
    final response = await httpClient.send(request);

    if (response.statusCode != HttpStatus.ok) {
      throw Exception(
        '''Failed to download file: ${response.statusCode} ${response.reasonPhrase}''',
      );
    }

    final File outFile;
    if (outputPath != null) {
      outFile = File(outputPath);
    } else {
      final tempDir = await Directory.systemTemp.createTemp();
      outFile = File(p.join(tempDir.path, 'artifact'));
    }

    if (!outFile.existsSync()) {
      outFile.createSync();
    }

    await outFile.openWrite().addStream(response.stream);
    return outFile.path;
  }

  /// Extracts the [zipFile] to the [outputDirectory] directory in a separate
  /// isolate.
  Future<void> extractZip({
    required File zipFile,
    required Directory outputDirectory,
  }) async {
    await Isolate.run(() async {
      final inputStream = InputFileStream(zipFile.path);
      final archive = ZipDecoder().decodeBuffer(inputStream);
      extractArchiveToDisk(archive, outputDirectory.path);
    });
  }
}

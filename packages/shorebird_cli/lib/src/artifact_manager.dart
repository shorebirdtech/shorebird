import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

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
  /// the downloaded [File].
  Future<File> downloadFile(
    Uri uri, {
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
    return outFile;
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
      inputStream.closeSync();
      extractArchiveToDisk(archive, outputDirectory.path);
    });
  }

  /// Returns the path to the directory containing the architecture-specific
  /// libraries for the given [flavor] (if provided). Will return null if no
  /// directory is found in the expected locations.
  /// Expected locations are:
  /// - `build/app/intermediates/stripped_native_libs/stripReleaseDebugSymbols/release/out/lib`
  /// - `build/app/intermediates/stripped_native_libs/strip{flavor}ReleaseDebugSymbols/{flavor}Release/out/lib`
  /// - `build/app/intermediates/stripped_native_libs/release/out/lib`
  /// - `build/app/intermediates/stripped_native_libs/{flavor}Release/out/lib`
  static Directory? androidArchsDirectory({
    required Directory projectRoot,
    String? flavor,
  }) {
    final releasePath = p.join(
      projectRoot.path,
      'build',
      'app',
      'intermediates',
      'stripped_native_libs',
      flavor != null ? '${flavor}Release' : 'release',
    );

    final String stripReleaseDebugSymbolsDirName;
    if (flavor != null) {
      // Capitalize the first letter of the flavor name.
      final flavorName =
          flavor.substring(0, 1).toUpperCase() + flavor.substring(1);
      stripReleaseDebugSymbolsDirName = 'strip${flavorName}ReleaseDebugSymbols';
    } else {
      stripReleaseDebugSymbolsDirName = 'stripReleaseDebugSymbols';
    }

    // An upgrade in the `com.android.application` Gradle plugin from 7.3.0 to
    // 8.3.0 introduced an extra directory layer named
    // "strip{flavor}ReleaseDebugSymbols". We check first for the new
    // directory and then fallback to the old one.
    //
    // See https://github.com/shorebirdtech/shorebird/issues/1798
    final strippedSymbolsDir = Directory(
      p.join(
        releasePath,
        stripReleaseDebugSymbolsDirName,
      ),
    );

    final Directory archsDirectory;
    if (strippedSymbolsDir.existsSync()) {
      archsDirectory = Directory(
        p.join(
          strippedSymbolsDir.path,
          'out',
          'lib',
        ),
      );
    } else {
      // If the new path doesn't exist, fallback to the old path.
      archsDirectory = Directory(
        p.join(
          releasePath,
          'out',
          'lib',
        ),
      );
    }

    return archsDirectory.existsSync() ? archsDirectory : null;
  }
}

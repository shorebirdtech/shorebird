// cspell:words archs xcarchive xcframework
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:stream_transform/stream_transform.dart';

/// A reference to a [ArtifactManager] instance.
final artifactManagerRef = create(ArtifactManager.new);

/// The [ArtifactManager] instance available in the current zone.
ArtifactManager get artifactManager => read(artifactManagerRef);

/// A callback that reports progress as a double between 0 and 1.
typedef ProgressCallback = void Function(double progress);

/// {@template file_download}
/// Used to monitor the progress of a file download and retrieve the file once
/// it has been downloaded.
/// {@endtemplate}
class FileDownload {
  /// {@macro file_download}
  FileDownload({required this.file, required this.progress});

  /// The file that is being downloaded. Await this to get the downloaded file.
  final Future<File> file;

  /// The progress of the download as a stream of doubles between 0 and 1.
  final Stream<double> progress;
}

/// Manages artifacts for the Shorebird CLI.
class ArtifactManager {
  /// Generates a binary diff between two files and returns the path to the
  /// output diff file.
  Future<String> createDiff({
    required String releaseArtifactPath,
    required String patchArtifactPath,
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

    final tempDir = await Directory.systemTemp.createTemp();
    final diffPath = p.join(tempDir.path, 'diff.patch');

    await patchExecutable.run(
      releaseArtifactPath: releaseArtifactPath,
      patchArtifactPath: patchArtifactPath,
      diffPath: diffPath,
    );

    return diffPath;
  }

  /// Downloads the file at the given [uri] to a [outputPath] if provided or a
  /// temporary directory if not.
  ///
  /// Returns the downloaded [File].
  Future<File> downloadFile(
    Uri uri, {
    String? outputPath,
  }) async {
    final download = await startFileDownload(
      uri,
      outputPath: outputPath,
    );
    return download.file;
  }

  /// Downloads the file at the given [uri] to a [outputPath] if provided or a
  /// temporary directory if not.
  ///
  /// Returns a [FileDownload] object containing the [Future<File>] and a
  /// [Stream] of download progress updates.
  @visibleForTesting
  Future<FileDownload> startFileDownload(
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
    final progressStreamController = StreamController<double>();

    Future<File> writeStreamedResponseToFile() async {
      final ioSink = outFile.openWrite();
      try {
        var downloadedBytes = 0;
        final totalBytes = response.contentLength;
        await for (final chunk in response.stream) {
          ioSink.add(chunk);
          downloadedBytes += chunk.length;
          if (totalBytes == null) {
            continue;
          }

          if (progressStreamController.hasListener) {
            progressStreamController.add(downloadedBytes / totalBytes);
          }
        }
      } finally {
        // Don't await, as this future will never complete if there are no
        // listeners.
        unawaited(progressStreamController.close());
        await ioSink.close();
      }

      return outFile;
    }

    return FileDownload(
      file: writeStreamedResponseToFile(),
      progress: progressStreamController.stream,
    );
  }

  /// Downloads the file at the given [uri] to a temporary location and logs
  /// progress updates as "[message] (XX%)". Progress updates happen at most
  /// once every 250 milliseconds. If the download fails, the progress message
  /// will be updated to "[message] failed: Exception", where "Exception" is the
  /// error message.
  ///
  /// Returns the downloaded [File].
  Future<File> downloadWithProgressUpdates(
    Uri uri, {
    required String message,
    Duration throttleDuration = const Duration(milliseconds: 250),
  }) async {
    final downloadProgress = logger.progress(message);
    final File artifactFile;
    try {
      final download = await startFileDownload(uri);
      final subscription = download.progress
          .throttle(throttleDuration, trailing: true)
          .listen((progress) {
        downloadProgress.update(
          '$message (${(progress * 100).toStringAsFixed(0)}%)',
        );
      });

      artifactFile = await download.file;
      await subscription.cancel();
      downloadProgress.complete('$message (100%)');
    } catch (e) {
      downloadProgress.fail('$message failed: $e');
      rethrow;
    }

    return artifactFile;
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
      await extractArchiveToDisk(archive, outputDirectory.path);
      inputStream.closeSync();
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

  /// Returns the .xcarchive directory generated by `flutter build ipa`. This
  /// was traditionally named `Runner.xcarchive`, but can now be renamed.
  Directory? getXcarchiveDirectory() {
    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    final archiveDirectory = Directory(
      p.join(
        projectRoot.path,
        'build',
        'ios',
        'archive',
      ),
    );

    if (!archiveDirectory.existsSync()) return null;

    final xcarchive = archiveDirectory
        .listSync()
        .whereType<Directory>()
        // Get the most recently modified xcarchive to handle cases where an app
        // may produce multiple xcarchives with different names.
        .sorted(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        )
        .firstWhereOrNull((directory) => directory.path.endsWith('.xcarchive'));
    return xcarchive;
  }

  /// Returns the .app directory generated by `flutter build ipa`. This was
  /// traditionally named `Runner.app`, but can now be renamed.
  Directory? getIosAppDirectory({required Directory xcarchiveDirectory}) {
    final applicationsDirectory = Directory(
      p.join(
        xcarchiveDirectory.path,
        'Products',
        'Applications',
      ),
    );

    if (!applicationsDirectory.existsSync()) {
      return null;
    }

    return applicationsDirectory
        .listSync()
        .whereType<Directory>()
        .firstWhereOrNull((directory) => directory.path.endsWith('.app'));
  }

  /// Returns the path to the .ipa file generated by `flutter build ipa`.
  ///
  /// Returns null if:
  ///  - there is no ipa build directory (build/ios/ipa)
  ///  - there is no .ipa file in the ipa build directory
  ///  - there is more than one .ipa file in the ipa build directory
  File? getIpa() {
    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    final ipaBuildDirectory = Directory(
      p.join(
        projectRoot.path,
        'build',
        'ios',
        'ipa',
      ),
    );

    if (!ipaBuildDirectory.existsSync()) {
      logger.detail('No directory found at ${ipaBuildDirectory.path}');
      return null;
    }

    final ipaFiles = ipaBuildDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => p.extension(f.path) == '.ipa');

    if (ipaFiles.isEmpty) {
      logger.detail('No .ipa files found in ${ipaBuildDirectory.path}');
      return null;
    }

    if (ipaFiles.length > 1) {
      logger.detail(
        'More than one .ipa file found in ${ipaBuildDirectory.path}',
      );
      return null;
    }

    return ipaFiles.single;
  }

  /// Name of the App.xcframework generated by `shorebird release ios-framework`
  static const String appXcframeworkName = 'App.xcframework';

  /// Returns the path to the App.xcframework generated by
  /// `shorebird release ios-framework` or
  /// `shorebird patch ios-framework`.
  String getAppXcframeworkPath() {
    return p.join(getAppXcframeworkDirectory().path, appXcframeworkName);
  }

  /// Returns the [Directory] containing the App.xcframework generated by
  /// `shorebird release ios-framework` or
  /// `shorebird patch ios-framework`.
  Directory getAppXcframeworkDirectory() {
    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    return Directory(
      p.join(
        projectRoot.path,
        'build',
        'ios',
        'framework',
        'Release',
      ),
    );
  }
}

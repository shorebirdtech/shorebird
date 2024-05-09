import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

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

    return archiveDirectory
        .listSync()
        .whereType<Directory>()
        .firstWhereOrNull((directory) => directory.path.endsWith('.xcarchive'));
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

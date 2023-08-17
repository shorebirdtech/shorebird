import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';

/// Finds differences between two IPAs or zipped Xcframeworks.
///
/// Asset changes will be in the `Assets.car` file (which is a combination of
/// the `.xcasset` catalogs in the Xcode project) and the `flutter_assets`
/// directory.
///
/// Native changes will appear in the Runner.app/Runner executable and non
///   Flutter.framework or App.framework files.
///
/// Dart changes will appear in the App.framework/App executable.
class IosArchiveDiffer extends ArchiveDiffer {
  String _hash(List<int> bytes) => sha256.convert(bytes).toString();

  static const binaryFiles = {
    'App.framework/App',
    'Flutter.framework/Flutter',
  };
  static RegExp appRegex = RegExp(r'^Payload/[\w\-. ]+.app/[\w\-. ]+$');

  /// Files that have been added, removed, or that have changed between the
  /// archives at the two provided paths. This method will also unisgn mach-o
  /// binaries in the archives before computing the diff.
  @override
  FileSetDiff changedFiles(String oldArchivePath, String newArchivePath) {
    final oldPathHashes = fileHashes(File(oldArchivePath));
    final newPathHashes = fileHashes(File(newArchivePath));

    _updateHashes(
      archivePath: oldArchivePath,
      pathHashes: oldPathHashes,
    );
    _updateHashes(
      archivePath: newArchivePath,
      pathHashes: newPathHashes,
    );

    return FileSetDiff.fromPathHashes(
      oldPathHashes: oldPathHashes,
      newPathHashes: newPathHashes,
    );
  }

  /// Replaces crc32s from zip file headers where needed. This currently
  /// includes:
  ///   - Signed files (those with a .app extension)
  ///   - Compiled asset catalogs (those with a .car extension)
  void _updateHashes({
    required String archivePath,
    required PathHashes pathHashes,
  }) {
    for (final file in _filesToUnsign(archivePath)) {
      pathHashes[file.name] = _unsignedFileHash(file);
    }

    for (final file in _carFiles(archivePath)) {
      pathHashes[file.name] = _carFileHash(file);
    }
  }

  List<ArchiveFile> _filesToUnsign(String archivePath) {
    return ZipDecoder()
        .decodeBuffer(InputFileStream(archivePath))
        .files
        .where((file) => file.isFile)
        .where(
          (file) =>
              file.name.endsWith('App.framework/App') ||
              file.name.endsWith('Flutter.framework/Flutter') ||
              appRegex.hasMatch(file.name),
        )
        .toList();
  }

  List<ArchiveFile> _carFiles(String archivePath) {
    return ZipDecoder()
        .decodeBuffer(InputFileStream(archivePath))
        .files
        .where((file) => file.isFile && p.extension(file.name) == '.car')
        .toList();
  }

  String _unsignedFileHash(ArchiveFile file) {
    final tempDir = Directory.systemTemp.createTempSync();
    final outPath = p.join(tempDir.path, file.name);
    final outputStream = OutputFileStream(outPath);
    file.writeContent(outputStream);
    outputStream.close();

    if (Platform.isMacOS) {
      // coverage:ignore-start
      Process.runSync('codesign', ['--remove-signature', outPath]);
      // coverage:ignore-end
    }

    final outFile = File(outPath);
    final hash = _hash(outFile.readAsBytesSync());
    return hash;
  }

  /// Uses assetutil to write a json description of a .car file to disk and
  /// diffs the contents of that file, less a timestamp line that chnages based
  /// on when the .car file was created.
  String _carFileHash(ArchiveFile file) {
    final tempDir = Directory.systemTemp.createTempSync();
    final outPath = p.join(tempDir.path, file.name);
    final outputStream = OutputFileStream(outPath);
    file.writeContent(outputStream);
    outputStream.close();

    final assetInfoPath = '$outPath.json';

    if (Platform.isMacOS) {
      // coverage:ignore-start
      Process.runSync('assetutil', ['--info', outPath, '-o', assetInfoPath]);
      // coverage:ignore-end
    } else {
      // This is just for testing
      File(assetInfoPath).createSync(recursive: true);
    }

    // Remove the timestamp line from the json file
    final jsonFile = File(assetInfoPath);
    final lines = jsonFile.readAsLinesSync();
    final timestampRegex = RegExp(r'^\W+"Timestamp" : \d+$');
    final linesToKeep = lines.whereNot(timestampRegex.hasMatch);
    return _hash(linesToKeep.join('\n').codeUnits);
  }

  @override
  bool containsPotentiallyBreakingAssetDiffs(FileSetDiff fileSetDiff) =>
      assetsFileSetDiff(fileSetDiff).isNotEmpty;

  @override
  bool containsPotentiallyBreakingNativeDiffs(FileSetDiff fileSetDiff) =>
      nativeFileSetDiff(fileSetDiff).isNotEmpty;

  @override
  bool isAssetFilePath(String filePath) {
    /// The flutter_assets directory contains the assets listed in the assets
    ///   section of the pubspec.yaml file.
    /// Assets.car is the compiled asset catalog(s) (.xcassets files).
    return p.extension(filePath) == '.car' ||
        p.split(filePath).contains('flutter_assets');
  }

  @override
  bool isDartFilePath(String filePath) =>
      filePath.endsWith('App.framework/App');

  @override
  bool isNativeFilePath(String filePath) => appRegex.hasMatch(filePath);
}

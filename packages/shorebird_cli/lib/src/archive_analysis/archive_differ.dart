import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';

/// Thrown when an [ArchiveDiffer] fails to generate a [FileSetDiff].
class DiffFailedException implements Exception {}

/// Computes content differences between two archives.
abstract class ArchiveDiffer {
  /// Asset files that are not considered to be breaking changes.
  static const assetFileNamesToIgnore = {
    'AssetManifest.bin',
    'AssetManifest.json',
    'NOTICES.Z',
  };

  /// Whether there are asset differences between the archives that may cause
  /// issues when patching a release.
  bool containsPotentiallyBreakingAssetDiffs(FileSetDiff fileSetDiff) {
    final assetsDiff = assetsFileSetDiff(fileSetDiff);

    // If assets were added, we need to warn the user about asset differences.
    if (assetsDiff.addedPaths.isNotEmpty) {
      return true;
    }

    return assetsDiff.changedPaths
        .whereNot(
          (path) =>
              ArchiveDiffer.assetFileNamesToIgnore.contains(p.basename(path)),
        )
        .isNotEmpty;
  }

  /// Whether there are native code differences between the archives that may
  /// cause issues when patching a release.
  bool containsPotentiallyBreakingNativeDiffs(FileSetDiff fileSetDiff);

  /// Whether the provided file path represents a changed asset.
  bool isAssetFilePath(String filePath);

  /// Whether the provided file path represents changed Dart code.
  bool isDartFilePath(String filePath);

  /// Whether the provided file path represents changed Native code.
  bool isNativeFilePath(String filePath);

  /// The subset of [fileSetDiff] that contains only changes that result from
  /// edited assets.
  FileSetDiff assetsFileSetDiff(FileSetDiff fileSetDiff) => FileSetDiff(
        addedPaths: fileSetDiff.addedPaths.where(isAssetFilePath).toSet(),
        removedPaths: fileSetDiff.removedPaths.where(isAssetFilePath).toSet(),
        changedPaths: fileSetDiff.changedPaths.where(isAssetFilePath).toSet(),
      );

  /// The subset of [fileSetDiff] that contains only changes that result from
  /// edited Dart code.
  FileSetDiff dartFileSetDiff(FileSetDiff fileSetDiff) => FileSetDiff(
        addedPaths: fileSetDiff.addedPaths.where(isDartFilePath).toSet(),
        removedPaths: fileSetDiff.removedPaths.where(isDartFilePath).toSet(),
        changedPaths: fileSetDiff.changedPaths.where(isDartFilePath).toSet(),
      );

  /// The subset of [fileSetDiff] that contains only changes that result from
  /// edited native code.
  FileSetDiff nativeFileSetDiff(FileSetDiff fileSetDiff) => FileSetDiff(
        addedPaths: fileSetDiff.addedPaths.where(isNativeFilePath).toSet(),
        removedPaths: fileSetDiff.removedPaths.where(isNativeFilePath).toSet(),
        changedPaths: fileSetDiff.changedPaths.where(isNativeFilePath).toSet(),
      );

  /// Files that have been added, removed, or that have changed between the
  /// archives at the two provided paths.
  Future<FileSetDiff> changedFiles(
    String oldArchivePath,
    String newArchivePath,
  ) async {
    return FileSetDiff.fromPathHashes(
      oldPathHashes: await fileHashes(File(oldArchivePath)),
      newPathHashes: await fileHashes(File(newArchivePath)),
    );
  }

  Future<PathHashes> fileHashes(File archive) async {
    return Isolate.run(() {
      final zipDirectory = ZipDirectory.read(InputFileStream(archive.path));

      return {
        for (final file in zipDirectory.fileHeaders)
          // Zip files contain an (optional) crc32 checksum for a file. IPAs and
          // AARs seem to always include this for files, so a quick way for us
          // to tell if file contents differ is if their checksums differ.
          file.filename: file.crc32!.toString(),
      };
    });
  }
}

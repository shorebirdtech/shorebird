import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';

abstract class AndroidArchiveDiffer extends ArchiveDiffer {
  @override
  bool containsPotentiallyBreakingAssetDiffs(FileSetDiff fileSetDiff) {
    // If only files in this set have changed, we don't need to warn the user
    // about asset differences.
    const assetFileNamesToIgnore = {
      'AssetManifest.bin',
      'AssetManifest.json',
      'NOTICES.Z',
    };

    final assetsDiff = assetsFileSetDiff(fileSetDiff);

    // If assets were added, we need to warn the user about asset differences.
    if (assetsDiff.addedPaths.isNotEmpty) {
      return true;
    }

    return assetsDiff.changedPaths
        .whereNot((path) => assetFileNamesToIgnore.contains(p.basename(path)))
        .isNotEmpty;
  }

  @override
  bool containsPotentiallyBreakingNativeDiffs(FileSetDiff fileSetDiff) =>
      nativeFileSetDiff(fileSetDiff).isNotEmpty;

  FileSetDiff assetsFileSetDiff(FileSetDiff fileSetDiff) => FileSetDiff(
        addedPaths: fileSetDiff.addedPaths.where(_isAssetFilePath).toSet(),
        removedPaths: fileSetDiff.removedPaths.where(_isAssetFilePath).toSet(),
        changedPaths: fileSetDiff.changedPaths.where(_isAssetFilePath).toSet(),
      );

  FileSetDiff dartFileSetDiff(FileSetDiff fileSetDiff) => FileSetDiff(
        addedPaths: fileSetDiff.addedPaths.where(_isDartFilePath).toSet(),
        removedPaths: fileSetDiff.removedPaths.where(_isDartFilePath).toSet(),
        changedPaths: fileSetDiff.changedPaths.where(_isDartFilePath).toSet(),
      );

  FileSetDiff nativeFileSetDiff(FileSetDiff fileSetDiff) => FileSetDiff(
        addedPaths: fileSetDiff.addedPaths.where(_isNativeFilePath).toSet(),
        removedPaths: fileSetDiff.removedPaths.where(_isNativeFilePath).toSet(),
        changedPaths: fileSetDiff.changedPaths.where(_isNativeFilePath).toSet(),
      );

  static bool _isAssetFilePath(String filePath) {
    const assetDirNames = ['assets', 'res'];
    const assetFileNames = ['AssetManifest.json'];

    return p
            .split(filePath)
            .any((component) => assetDirNames.contains(component)) ||
        assetFileNames.contains(p.basename(filePath));
  }

  static bool _isDartFilePath(String filePath) {
    const dartFileNames = ['libapp.so', 'libflutter.so'];
    return dartFileNames.contains(p.basename(filePath));
  }

  static bool _isNativeFilePath(String filePath) =>
      p.extension(filePath) == '.dex';
}

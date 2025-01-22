import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';

/// {@template windows_archive_differ}
/// Finds differences between two Windows app packages.
/// {@endtemplate}
class WindowsArchiveDiffer extends ArchiveDiffer {
  /// {@macro windows_archive_differ}
  const WindowsArchiveDiffer();

  bool _isDirectoryPath(String path) {
    return path.endsWith('/');
  }

  @override
  bool isAssetFilePath(String filePath) {
    // We don't care if an empty directory is added or removed, so ignore paths
    // that end with a '/'.
    return !_isDirectoryPath(filePath) &&
        p.split(filePath).contains('flutter_assets');
  }

  @override
  bool isDartFilePath(String filePath) {
    return p.basename(filePath) == 'app.so';
  }

  @override
  bool isNativeFilePath(String filePath) {
    // We can't reliably detect native changes in Windows patches, so we don't
    // attempt to diff them.
    //
    // Creating a release on one Windows machine and then attempting to patch
    // on another results in a large number of changes to the exe and any dll
    // files it requires that are spread throughout the file and very noisy.
    //
    // Otherwise, this function would return true if the file has a .dll or .exe
    // extension.
    //
    // See https://github.com/shorebirdtech/shorebird/issues/2794
    return false;
  }

  @override
  Future<FileSetDiff> changedFiles(
    String oldArchivePath,
    String newArchivePath,
  ) async {
    final oldPathHashes = await fileHashes(File(oldArchivePath));
    final newPathHashes = await fileHashes(File(newArchivePath));
    return FileSetDiff.fromPathHashes(
      oldPathHashes: oldPathHashes,
      newPathHashes: newPathHashes,
    );
  }
}

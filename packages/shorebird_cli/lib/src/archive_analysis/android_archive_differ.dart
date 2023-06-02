import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';

abstract class AndroidArchiveDiffer {
  /// Files that have changed between the archives at the two provided paths.
  Set<String> changedFiles(String archivePath1, String archivePath2);

  /// Whether any changed files correspond to a change in assets.
  bool hasAssetChanges(Set<String> paths) {
    const assetDirNames = ['assets', 'res'];
    const assetFileNames = ['AssetManifest.json'];
    return paths.any(
      (path) =>
          p.split(path).any((component) => assetDirNames.contains(component)) ||
          assetFileNames.contains(p.basename(path)),
    );
  }

  /// Whether any changed files correspond to a change in Dart code.
  bool hasDartChanges(Set<String> paths) {
    const dartFileNames = ['libapp.so', 'libflutter.so'];
    return paths.any((path) => dartFileNames.contains(p.basename(path)));
  }

  /// Whether changed files correspond to a change in Java or Kotlin code.
  bool hasNativeChanges(Set<String> path) {
    return path.any((path) => p.extension(path) == '.dex');
  }

  Set<ArchiveDifferences> contentDifferences(
    String archivePath1,
    String archivePath2,
  ) {
    final changedFilePaths = changedFiles(archivePath1, archivePath2);
    final differences = <ArchiveDifferences>{};
    if (hasDartChanges(changedFilePaths)) {
      differences.add(ArchiveDifferences.dart);
    }
    if (hasAssetChanges(changedFilePaths)) {
      differences.add(ArchiveDifferences.assets);
    }
    if (hasNativeChanges(changedFilePaths)) {
      differences.add(ArchiveDifferences.native);
    }

    return differences;
  }
}

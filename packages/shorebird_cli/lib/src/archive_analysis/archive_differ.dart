import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';

/// Computes content differences between two archives.
abstract class ArchiveDiffer {
  /// Files that have been added, removed, or that have changed between the
  /// archives at the two provided paths.
  FileSetDiff changedFiles(String oldArchivePath, String newArchivePath);

  /// Whether any changed files correspond to a change in assets.
  static Set<String> assetChanges(Set<String> paths) {
    const assetDirNames = ['assets', 'res'];
    const assetFileNames = ['AssetManifest.json'];
    return paths
        .where(
          (path) =>
              p
                  .split(path)
                  .any((component) => assetDirNames.contains(component)) ||
              assetFileNames.contains(p.basename(path)),
        )
        .toSet();
  }

  /// Whether any changed files correspond to a change in Dart code.
  static Set<String> dartChanges(Set<String> paths) {
    const dartFileNames = ['libapp.so', 'libflutter.so'];
    return paths
        .where((path) => dartFileNames.contains(p.basename(path)))
        .toSet();
  }

  /// Whether changed files correspond to a change in native code.
  static Set<String> nativeChanges(Set<String> path) {
    // TODO(bryanoltman): add support for iOS native code changes.
    return path.where((path) => p.extension(path) == '.dex').toSet();
  }
}

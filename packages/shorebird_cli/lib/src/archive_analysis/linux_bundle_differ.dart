import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';

/// {@template linux_bundle_differ}
/// Finds differences between two Linux bundles.
/// {@endtemplate}
class LinuxBundleDiffer extends ArchiveDiffer {
  /// {@macro linux_bundle_differ}
  const LinuxBundleDiffer();

  @override
  bool isAssetFilePath(String filePath) =>
      p.split(filePath).any((s) => s == 'flutter_assets');

  @override
  bool isDartFilePath(String filePath) => p.basename(filePath) == 'libapp.so';

  @override
  bool isNativeFilePath(String filePath) {
    // TODO: implement isNativeFilePath
    return false;
  }
}

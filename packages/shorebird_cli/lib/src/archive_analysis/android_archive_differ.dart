import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';

abstract class AndroidArchiveDiffer extends ArchiveDiffer {
  @override
  bool containsPotentiallyBreakingNativeDiffs(FileSetDiff fileSetDiff) =>
      nativeFileSetDiff(fileSetDiff).isNotEmpty;

  @override
  bool isAssetFilePath(String filePath) {
    const assetDirNames = ['assets', 'res'];
    const assetFileNames = ['AssetManifest.json'];

    return p
            .split(filePath)
            .any((component) => assetDirNames.contains(component)) ||
        assetFileNames.contains(p.basename(filePath));
  }

  @override
  bool isDartFilePath(String filePath) {
    const dartFileNames = ['libapp.so', 'libflutter.so'];
    return dartFileNames.contains(p.basename(filePath));
  }

  @override
  bool isNativeFilePath(String filePath) => p.extension(filePath) == '.dex';
}

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';

/// Finds differences between two Android archives (either AABs or AARs).
///
/// Types of changes we care about:
///   - Dart code changes
///      - libapp.so will be different
///   - Java/Kotlin code changes
///      - .dex files will be different
///   - Assets
///      - **/assets/** will be different
///      - AssetManifest.json will have changed if assets have been added or
///        removed
///
/// Changes we don't care about:
///   - Anything in META-INF
///   - BUNDLE-METADATA/com.android.tools.build.libraries/dependencies.pb
///      - This seems to change with every build, regardless of whether any code
///        or assets were changed.
///
/// See https://developer.android.com/guide/app-bundle/app-bundle-format and
/// /// https://developer.android.com/studio/projects/android-library.html#aar-contents
/// for reference. Note that .aars produced by Flutter modules do not contain
/// .jar files, so only asset and dart changes are possible.
class AndroidArchiveDiffer extends ArchiveDiffer {
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

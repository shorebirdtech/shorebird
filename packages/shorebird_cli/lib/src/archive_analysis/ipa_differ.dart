import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';

/// Finds differences between two IPAs.
///
/// Asset changes will be in the `Assets.car` file (which is a combination of
/// the `.xcasset` catalogs in the Xcode project) and the `flutter_assets`
/// directory.
///
/// Native changes will appear in the Runner.app/Runner executable.
///
/// Dart changes will appear in the App.framework/App executable.
class IpaDiffer extends ArchiveDiffer {
  static const binaryFiles = {
    'App.framework/App',
    'Flutter.framework/Flutter',
  };
  static RegExp appRegex = RegExp(r'^Payload/[\w\-. ]+.app/[\w\-. ]+$');

  @override
  bool containsPotentiallyBreakingAssetDiffs(FileSetDiff fileSetDiff) =>
      assetsFileSetDiff(fileSetDiff).isNotEmpty;

  @override
  bool containsPotentiallyBreakingNativeDiffs(FileSetDiff fileSetDiff) {
    // Because the mach-o binaries are signed, they will always have different
    // hashes, even if the code used to generate them is identical.
    //
    // TODO(bryanoltman): support mach-o binary diffing.
    // We can do this using the `codesign --remove-signature` command, but this
    // is slow and requires a temporary directory to store the unsigned binary.
    return false;
  }

  @override
  bool isAssetFilePath(String filePath) {
    /// The flutter_assets directory contains the assets listed in the assets
    ///   section of the pubspec.yaml file.
    /// Assets.car is the compiled asset catalog(s) (.xcassets files).
    return p.basename(filePath) == 'Assets.car' ||
        p.split(filePath).contains('flutter_assets');
  }

  @override
  bool isDartFilePath(String filePath) =>
      filePath.endsWith('App.framework/App');

  @override
  bool isNativeFilePath(String filePath) => appRegex.hasMatch(filePath);
}

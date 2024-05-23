import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';
import 'package:test/test.dart';

void main() {
  group(ArchiveDiffer, () {
    late TestArchiveDiffer archiveDiffer;

    setUp(() {
      archiveDiffer = TestArchiveDiffer();
    });

    group('containsPotentiallyBreakingAssetDiffs', () {
      test('returns true if any assets were added', () {
        final changedFileSetDiff = FileSetDiff(
          addedPaths: {'assets/asset1.png'},
          removedPaths: {},
          changedPaths: {},
        );
        expect(
          archiveDiffer.containsPotentiallyBreakingAssetDiffs(
            changedFileSetDiff,
          ),
          isTrue,
        );
      });

      test('returns false if changed assets are all in the ignore list', () {
        final changedFileSetDiff = FileSetDiff(
          addedPaths: {},
          removedPaths: {},
          changedPaths: {
            'assets/AssetManifest.bin',
            'assets/NOTICES.Z',
            'assets/shorebird.yaml',
          },
        );
        expect(
          archiveDiffer.containsPotentiallyBreakingAssetDiffs(
            changedFileSetDiff,
          ),
          isFalse,
        );
      });

      test('returns true if changed assets are not all in the ignore list', () {
        final changedFileSetDiff = FileSetDiff(
          addedPaths: {},
          removedPaths: {},
          changedPaths: {
            'assets/AssetManifest.bin',
            'assets/unignored_asset.png',
          },
        );
        expect(
          archiveDiffer.containsPotentiallyBreakingAssetDiffs(
            changedFileSetDiff,
          ),
          isTrue,
        );
      });
    });
  });
}

/// An implementation of the abstract [ArchiveDiffer] class for testing.
/// [ArchiveDiffer] only implements [containsPotentiallyBreakingAssetDiffs], so
/// only method relevant to that method are implemented here.
class TestArchiveDiffer extends ArchiveDiffer {
  // This method is implemented by subclasses. For our purposes, a path will be
  // considered an asset if it starts with 'assets/'
  @override
  bool isAssetFilePath(String filePath) => filePath.startsWith('assets/');

  // The following methods are irrelevant to checking for asset changes.
  @override
  bool containsPotentiallyBreakingNativeDiffs(FileSetDiff fileSetDiff) => false;

  @override
  bool isDartFilePath(String filePath) => true;

  @override
  bool isNativeFilePath(String filePath) => true;
}

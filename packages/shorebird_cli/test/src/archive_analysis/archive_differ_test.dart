import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';
import 'package:test/test.dart';

const assetFilePath = 'some/assets/file';

void main() {
  group(ArchiveDiffer, () {
    late TestArchiveDiffer archiveDiffer;

    setUp(() {
      archiveDiffer = TestArchiveDiffer();
    });

    group('containsPotentiallyBreakingAssetDiffs', () {
      test('returns true if any assets were added', () {
        archiveDiffer.changedFileSetDiff = FileSetDiff(
          addedPaths: {assetFilePath},
          removedPaths: {},
          changedPaths: {},
        );
        expect(
          archiveDiffer.containsPotentiallyBreakingAssetDiffs(
            archiveDiffer.changedFileSetDiff,
          ),
          isTrue,
        );
      });

      test('returns false if changed assets are all in the ignore list', () {
        archiveDiffer.changedFileSetDiff = FileSetDiff(
          addedPaths: {},
          removedPaths: {},
          changedPaths: {'AssetManifest.bin'},
        );
        expect(
          archiveDiffer.containsPotentiallyBreakingAssetDiffs(
            archiveDiffer.changedFileSetDiff,
          ),
          isFalse,
        );
      });

      test('returns true if changed assets are not all in the ignore list', () {
        archiveDiffer.changedFileSetDiff = FileSetDiff(
          addedPaths: {},
          removedPaths: {},
          changedPaths: {assetFilePath},
        );
        expect(
          archiveDiffer.containsPotentiallyBreakingAssetDiffs(
            archiveDiffer.changedFileSetDiff,
          ),
          isTrue,
        );
      });
    });
  });
}

class TestArchiveDiffer extends ArchiveDiffer {
  FileSetDiff changedFileSetDiff = FileSetDiff.empty();

  @override
  FileSetDiff changedFiles(String oldArchivePath, String newArchivePath) =>
      changedFileSetDiff;

  @override
  bool containsPotentiallyBreakingNativeDiffs(FileSetDiff fileSetDiff) => false;

  @override
  bool isAssetFilePath(String filePath) => filePath == assetFilePath;

  @override
  bool isDartFilePath(String filePath) => true;

  @override
  bool isNativeFilePath(String filePath) => true;
}

import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';
import 'package:test/test.dart';

void main() {
  group(AndroidArchiveDiffer, () {
    late TestAndroidArchiveDiffer differ;

    setUp(() {
      differ = TestAndroidArchiveDiffer();
    });

    group('containsPotentiallyBreakingAssetDiffs', () {
      test('returns true if assets were added', () {
        final fileSetDiff = FileSetDiff(
          addedPaths: {'base/assets/flutter_assets/file.json'},
          removedPaths: {},
          changedPaths: {},
        );
        expect(
          differ.containsPotentiallyBreakingAssetDiffs(fileSetDiff),
          isTrue,
        );
      });

      test('returns true if changed assets are not in the ignore list', () {
        final fileSetDiff = FileSetDiff(
          addedPaths: {},
          removedPaths: {},
          changedPaths: {
            'AssetManifest.bin',
            'AssetManifest.json',
            'base/assets/file.json',
          },
        );
        expect(
          differ.containsPotentiallyBreakingAssetDiffs(fileSetDiff),
          isTrue,
        );
      });

      test('returns false if changed assets are in the ignore list', () {
        final fileSetDiff = FileSetDiff(
          addedPaths: {},
          removedPaths: {},
          changedPaths: {
            'base/assets/flutter_assets/AssetManifest.bin',
            'base/assets/flutter_assets/AssetManifest.json',
            'base/assets/flutter_assets/NOTICES.Z',
          },
        );
        expect(
          differ.containsPotentiallyBreakingAssetDiffs(fileSetDiff),
          isFalse,
        );
      });
    });

    group('containsPotentiallyBreakingNativeDiffs', () {
      test('returns true if any native files have been added', () {
        final fileSetDiff = FileSetDiff(
          addedPaths: {'base/lib/arm64-v8a/test.dex'},
          removedPaths: {},
          changedPaths: {},
        );
        expect(
          differ.containsPotentiallyBreakingNativeDiffs(fileSetDiff),
          isTrue,
        );
      });

      test('returns true if any native files have been removed', () {
        final fileSetDiff = FileSetDiff(
          addedPaths: {},
          removedPaths: {'base/lib/arm64-v8a/test.dex'},
          changedPaths: {},
        );
        expect(
          differ.containsPotentiallyBreakingNativeDiffs(fileSetDiff),
          isTrue,
        );
      });

      test('returns true if any native files have been changed', () {
        final fileSetDiff = FileSetDiff(
          addedPaths: {},
          removedPaths: {},
          changedPaths: {'base/lib/arm64-v8a/test.dex'},
        );
        expect(
          differ.containsPotentiallyBreakingNativeDiffs(fileSetDiff),
          isTrue,
        );
      });

      test('returns false if no native files have been changed', () {
        final fileSetDiff = FileSetDiff.empty();
        expect(
          differ.containsPotentiallyBreakingNativeDiffs(fileSetDiff),
          isFalse,
        );
      });
    });
  });
}

/// An empty subclass of [AndroidArchiveDiffer] to allow instantiation.
class TestAndroidArchiveDiffer extends AndroidArchiveDiffer {
  @override
  FileSetDiff changedFiles(String oldArchivePath, String newArchivePath) =>
      FileSetDiff.empty();
}

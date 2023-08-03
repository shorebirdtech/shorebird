import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';
import 'package:test/test.dart';

void main() {
  group(AndroidArchiveDiffer, () {
    final aabFixturesBasePath = p.join('test', 'fixtures', 'aabs');
    final baseAabPath = p.join(aabFixturesBasePath, 'base.aab');
    final changedAssetAabPath =
        p.join(aabFixturesBasePath, 'changed_asset.aab');
    final changedDartAabPath = p.join(aabFixturesBasePath, 'changed_dart.aab');
    final changedKotlinAabPath =
        p.join(aabFixturesBasePath, 'changed_kotlin.aab');
    final changedDartAndAssetAabPath =
        p.join(aabFixturesBasePath, 'changed_dart_and_asset.aab');

    final aarFixturesBasePath = p.join('test', 'fixtures', 'aars');
    final baseAarPath = p.join(aarFixturesBasePath, 'base.aar');
    final changedAssetAarPath =
        p.join(aarFixturesBasePath, 'changed_asset.aar');
    final changedDartAarPath = p.join(aarFixturesBasePath, 'changed_dart.aar');
    final changedDartAndAssetAarPath =
        p.join(aarFixturesBasePath, 'changed_dart_and_asset.aar');

    late AndroidArchiveDiffer differ;

    setUp(() {
      differ = AndroidArchiveDiffer();
    });

    group('aab', () {
      group('changedFiles', () {
        test('finds no differences between the same aab', () {
          expect(differ.changedFiles(baseAabPath, baseAabPath), isEmpty);
        });

        test('finds differences between two different aabs', () {
          expect(
            differ.changedFiles(baseAabPath, changedDartAabPath).changedPaths,
            {
              'BUNDLE-METADATA/com.android.tools.build.libraries/dependencies.pb',
              'base/lib/arm64-v8a/libapp.so',
              'base/lib/armeabi-v7a/libapp.so',
              'base/lib/x86_64/libapp.so',
              'META-INF/ANDROIDD.SF',
              'META-INF/ANDROIDD.RSA',
              'META-INF/MANIFEST.MF'
            },
          );
        });
      });

      group('contentDifferences', () {
        test('detects no differences between the same aab', () {
          expect(differ.changedFiles(baseAabPath, baseAabPath), isEmpty);
        });

        test('detects asset changes', () {
          final fileSetDiff =
              differ.changedFiles(baseAabPath, changedAssetAabPath);
          expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });

        test('detects kotlin changes', () {
          final fileSetDiff =
              differ.changedFiles(baseAabPath, changedKotlinAabPath);
          expect(differ.assetsFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isNotEmpty);
        });

        test('detects dart changes', () {
          final fileSetDiff =
              differ.changedFiles(baseAabPath, changedDartAabPath);
          expect(differ.assetsFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });

        test('detects dart and asset changes', () {
          final fileSetDiff =
              differ.changedFiles(baseAabPath, changedDartAndAssetAabPath);
          expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });
      });
    });

    group('aar', () {
      group('changedFiles', () {
        test('finds no differences between the same aar', () {
          expect(differ.changedFiles(baseAarPath, baseAarPath), isEmpty);
        });

        test('finds differences between two different aars', () {
          expect(
            differ.changedFiles(baseAarPath, changedDartAarPath).changedPaths,
            {'jni/arm64-v8a/libapp.so'},
          );
        });
      });

      group('changedFiles', () {
        test('detects no differences between the same aar', () {
          expect(differ.changedFiles(baseAarPath, baseAarPath), isEmpty);
        });

        test('detects asset changes', () {
          final fileSetDiff =
              differ.changedFiles(baseAarPath, changedAssetAarPath);
          expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });

        test('detects dart changes', () {
          final fileSetDiff =
              differ.changedFiles(baseAarPath, changedDartAarPath);
          expect(differ.assetsFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });

        test('detects dart and asset changes', () {
          final fileSetDiff =
              differ.changedFiles(baseAarPath, changedDartAndAssetAarPath);
          expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });
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
  });
}

/// An empty subclass of [AndroidArchiveDiffer] to allow instantiation.
// class TestAndroidArchiveDiffer extends AndroidArchiveDiffer {
//   @override
//   FileSetDiff changedFiles(String oldArchivePath, String newArchivePath) =>
//       FileSetDiff.empty();
// }

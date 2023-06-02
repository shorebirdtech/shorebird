import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:test/test.dart';

void main() {
  group(AabDiffer, () {
    final aabFixturesBasePath = p.join('test', 'fixtures', 'aabs');
    final baseAabPath = p.join(aabFixturesBasePath, 'base.aab');
    final changedAssetAabPath =
        p.join(aabFixturesBasePath, 'changed_asset.aab');
    final changedDartAabPath = p.join(aabFixturesBasePath, 'changed_dart.aab');
    final changedKotlinAabPath =
        p.join(aabFixturesBasePath, 'changed_kotlin.aab');
    final changedDartAndAssetAabPath =
        p.join(aabFixturesBasePath, 'changed_dart_and_asset.aab');

    late AabDiffer differ;

    setUp(() {
      differ = AabDiffer();
    });

    group('changedFiles', () {
      test('finds no differences between the same aab', () {
        expect(differ.changedFiles(baseAabPath, baseAabPath), isEmpty);
      });

      test('finds differences between two different aabs', () {
        expect(
          differ.changedFiles(baseAabPath, changedDartAabPath).toSet(),
          {
            'BUNDLE-METADATA/com.android.tools.build.libraries/dependencies.pb',
            'base/lib/arm64-v8a/libapp.so',
            'base/lib/armeabi-v7a/libapp.so',
            'base/lib/x86_64/libapp.so',
          },
        );
      });
    });

    group('contentDifferences', () {
      test('detects no differences between the same aab', () {
        expect(differ.contentDifferences(baseAabPath, baseAabPath), isEmpty);
      });

      test('detects asset changes', () {
        expect(
          differ.contentDifferences(baseAabPath, changedAssetAabPath),
          {ArchiveDifferences.assets},
        );
      });

      test('detects kotlin changes', () {
        expect(
          differ.contentDifferences(baseAabPath, changedKotlinAabPath),
          {ArchiveDifferences.native},
        );
      });

      test('detects dart changes', () {
        expect(
          differ.contentDifferences(baseAabPath, changedDartAabPath),
          {ArchiveDifferences.dart},
        );
      });

      test('detects dart and asset changes', () {
        expect(
          differ.contentDifferences(baseAabPath, changedDartAndAssetAabPath),
          {
            ArchiveDifferences.assets,
            ArchiveDifferences.dart,
          },
        );
      });
    });
  });
}

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/aab/aab.dart';
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

    group('aabFileDifferences', () {
      test('finds no differences between the same aab', () {
        expect(differ.aabChangedFiles(baseAabPath, baseAabPath), isEmpty);
      });

      test('finds differences between the two different aabs', () {
        expect(
          differ.aabChangedFiles(baseAabPath, changedDartAabPath).toSet(),
          {
            'BUNDLE-METADATA/com.android.tools.build.libraries/dependencies.pb',
            'base/lib/arm64-v8a/libapp.so',
            'base/lib/armeabi-v7a/libapp.so',
            'base/lib/x86_64/libapp.so',
          },
        );
      });
    });

    group('aabContentDifferences', () {
      test('detects no differences between the same aab', () {
        expect(differ.aabContentDifferences(baseAabPath, baseAabPath), isEmpty);
      });

      test('detects asset changes', () {
        expect(
          differ.aabContentDifferences(baseAabPath, changedAssetAabPath),
          {AabDifferences.assets},
        );
      });

      test('detects kotlin changes', () {
        expect(
          differ.aabContentDifferences(baseAabPath, changedKotlinAabPath),
          {AabDifferences.native},
        );
      });

      test('detects dart changes', () {
        expect(
          differ.aabContentDifferences(baseAabPath, changedDartAabPath),
          {AabDifferences.dart},
        );
      });

      test('detects dart and asset changes', () {
        expect(
          differ.aabContentDifferences(baseAabPath, changedDartAndAssetAabPath),
          {
            AabDifferences.assets,
            AabDifferences.dart,
          },
        );
      });
    });
  });
}

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

    group('changedPaths', () {
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
        expect(fileSetDiff.assetChanges.isEmpty, isFalse);
        expect(fileSetDiff.dartChanges.isEmpty, isTrue);
        expect(fileSetDiff.nativeChanges.isEmpty, isTrue);
      });

      test('detects kotlin changes', () {
        final fileSetDiff =
            differ.changedFiles(baseAabPath, changedKotlinAabPath);
        expect(fileSetDiff.assetChanges.isEmpty, isTrue);
        expect(fileSetDiff.dartChanges.isEmpty, isTrue);
        expect(fileSetDiff.nativeChanges.isEmpty, isFalse);
      });

      test('detects dart changes', () {
        final fileSetDiff =
            differ.changedFiles(baseAabPath, changedDartAabPath);
        expect(fileSetDiff.assetChanges.isEmpty, isTrue);
        expect(fileSetDiff.dartChanges.isEmpty, isFalse);
        expect(fileSetDiff.nativeChanges.isEmpty, isTrue);
      });

      test('detects dart and asset changes', () {
        final fileSetDiff =
            differ.changedFiles(baseAabPath, changedDartAndAssetAabPath);
        expect(fileSetDiff.assetChanges.isEmpty, isFalse);
        expect(fileSetDiff.dartChanges.isEmpty, isFalse);
        expect(fileSetDiff.nativeChanges.isEmpty, isTrue);
      });
    });
  });
}

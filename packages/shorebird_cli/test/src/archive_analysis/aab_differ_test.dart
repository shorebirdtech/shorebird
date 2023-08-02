import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
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
    final noManifestAabPath = p.join(aabFixturesBasePath, 'no_manifest.aab');

    late AabDiffer differ;

    setUp(() {
      differ = AabDiffer();
    });

    test('does not crash if MANIFEST.MF is missing', () {
      expect(
        () => differ.changedFiles(baseAabPath, noManifestAabPath),
        throwsA(isA<DiffFailedException>()),
      );
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
}

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:test/test.dart';

void main() {
  final aarFixturesBasePath = p.join('test', 'fixtures', 'aars');
  final baseAarPath = p.join(aarFixturesBasePath, 'base.aar');
  final changedAssetAarPath = p.join(aarFixturesBasePath, 'changed_asset.aar');
  final changedDartAarPath = p.join(aarFixturesBasePath, 'changed_dart.aar');
  final changedDartAndAssetAarPath =
      p.join(aarFixturesBasePath, 'changed_dart_and_asset.aar');

  late AarDiffer differ;

  setUp(() {
    differ = AarDiffer();
  });

  group('changedFiles', () {
    test('finds no differences between the same aar', () {
      expect(differ.changedFiles(baseAarPath, baseAarPath), isEmpty);
    });

    test('finds differences between two different aars', () {
      expect(
        differ.changedFiles(baseAarPath, changedDartAarPath).toSet(),
        {
          'jni/arm64-v8a/libapp.so',
        },
      );
    });
  });

  group('contentDifferences', () {
    test('detects no differences between the same aar', () {
      expect(differ.contentDifferences(baseAarPath, baseAarPath), isEmpty);
    });

    test('detects asset changes', () {
      expect(
        differ.contentDifferences(baseAarPath, changedAssetAarPath),
        {ArchiveDifferences.assets},
      );
    });

    test('detects dart changes', () {
      expect(
        differ.contentDifferences(baseAarPath, changedDartAarPath),
        {ArchiveDifferences.dart},
      );
    });

    test('detects dart and asset changes', () {
      expect(
        differ.contentDifferences(baseAarPath, changedDartAndAssetAarPath),
        {
          ArchiveDifferences.assets,
          ArchiveDifferences.dart,
        },
      );
    });
  });
}

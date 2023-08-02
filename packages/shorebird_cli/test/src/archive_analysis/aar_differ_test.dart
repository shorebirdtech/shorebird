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
    test('detects no differences between the same aar', () {
      expect(differ.changedFiles(baseAarPath, baseAarPath), isEmpty);
    });

    test('detects asset changes', () {
      final fileSetDiff = differ.changedFiles(baseAarPath, changedAssetAarPath);
      expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
      expect(differ.dartFileSetDiff(fileSetDiff), isEmpty);
      expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
    });

    test('detects dart changes', () {
      final fileSetDiff = differ.changedFiles(baseAarPath, changedDartAarPath);
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
}

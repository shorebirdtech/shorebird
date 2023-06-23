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

  group('changedPaths', () {
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
      final fileSetDiff = differ.changedFiles(baseAarPath, changedAssetAarPath);
      expect(fileSetDiff.assetChanges.isEmpty, isFalse);
      expect(fileSetDiff.dartChanges.isEmpty, isTrue);
      expect(fileSetDiff.nativeChanges.isEmpty, isTrue);
    });

    test('detects dart changes', () {
      final fileSetDiff = differ.changedFiles(baseAarPath, changedDartAarPath);
      expect(fileSetDiff.assetChanges.isEmpty, isTrue);
      expect(fileSetDiff.dartChanges.isEmpty, isFalse);
      expect(fileSetDiff.nativeChanges.isEmpty, isTrue);
    });

    test('detects dart and asset changes', () {
      final fileSetDiff =
          differ.changedFiles(baseAarPath, changedDartAndAssetAarPath);
      expect(fileSetDiff.assetChanges.isEmpty, isFalse);
      expect(fileSetDiff.dartChanges.isEmpty, isFalse);
      expect(fileSetDiff.nativeChanges.isEmpty, isTrue);
    });
  });
}

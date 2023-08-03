import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:test/test.dart';

void main() {
  final ipaFixturesBasePath = p.join('test', 'fixtures', 'ipas');
  final baseIpaPath = p.join(ipaFixturesBasePath, 'base.ipa');
  final changedAssetIpaPath = p.join(ipaFixturesBasePath, 'asset_changes.ipa');
  final changedDartIpaPath = p.join(ipaFixturesBasePath, 'dart_changes.ipa');
  final changedSwiftIpaPath = p.join(ipaFixturesBasePath, 'swift_changes.ipa');

  late IpaDiffer differ;

  setUp(() {
    differ = IpaDiffer();
  });

  group(IpaDiffer, () {
    group('changedPaths', () {
      test('finds no differences between the same ipa', () {
        expect(differ.changedFiles(baseIpaPath, baseIpaPath), isEmpty);
      });

      test('finds differences between two different ipas', () {
        expect(
          differ.changedFiles(baseIpaPath, changedAssetIpaPath).changedPaths,
          {
            'Payload/Runner.app/_CodeSignature/CodeResources',
            'Payload/Runner.app/Frameworks/App.framework/_CodeSignature/CodeResources',
            'Payload/Runner.app/Frameworks/App.framework/flutter_assets/assets/asset.json',
            'Symbols/4C4C4411-5555-3144-A13A-E47369D8ACD5.symbols',
            'Symbols/BC970605-0A53-3457-8736-D7A870AB6E71.symbols',
            'Symbols/0CBBC9EF-0745-3074-81B7-765F5B4515FD.symbols'
          },
        );
      });
    });

    group('changedFiles', () {
      test('detects asset changes', () {
        final fileSetDiff =
            differ.changedFiles(baseIpaPath, changedAssetIpaPath);
        expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
        expect(differ.dartFileSetDiff(fileSetDiff), isEmpty);
        expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
      });

      test('detects dart changes', () {
        final fileSetDiff =
            differ.changedFiles(baseIpaPath, changedDartIpaPath);
        expect(differ.assetsFileSetDiff(fileSetDiff), isEmpty);
        expect(differ.dartFileSetDiff(fileSetDiff), isNotEmpty);
        expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
      });

      test('detects swift changes', () {
        final fileSetDiff =
            differ.changedFiles(baseIpaPath, changedSwiftIpaPath);
        expect(differ.assetsFileSetDiff(fileSetDiff), isEmpty);
        expect(differ.dartFileSetDiff(fileSetDiff), isEmpty);
        expect(differ.nativeFileSetDiff(fileSetDiff), isNotEmpty);
      });
    });
  });
}

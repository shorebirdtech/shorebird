import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:test/test.dart';

void main() {
  final ipaFixturesBasePath = p.join('test', 'fixtures', 'ipas');
  final baseIpaBath = p.join(ipaFixturesBasePath, 'base.ipa');
  final changedAssetIpaBath = p.join(ipaFixturesBasePath, 'asset_changes.ipa');
  final changedDartIpaBath = p.join(ipaFixturesBasePath, 'dart_changes.ipa');

  late IpaDiffer differ;

  setUp(() {
    differ = IpaDiffer();
  });

  group(IpaDiffer, () {
    group('changedPaths', () {
      test('finds no differences between the same ipa', () {
        expect(differ.changedFiles(baseIpaBath, baseIpaBath), isEmpty);
      });

      test('finds differences between two different ipas', () {
        expect(
          differ.changedFiles(baseIpaBath, changedDartIpaBath).changedPaths,
          {
            'Payload/Runner.app/_CodeSignature/CodeResources',
            'Payload/Runner.app/Runner',
            'Symbols/4C4C4411-5555-3144-A13A-E47369D8ACD5.symbols',
            'Symbols/BC970605-0A53-3457-8736-D7A870AB6E71.symbols'
          },
        );
      });
    });

    group('changedFiles', () {
      test('detects asset changes', () {
        final fileSetDiff =
            differ.changedFiles(baseIpaBath, changedAssetIpaBath);
        expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
        // Dart changes are reflected in .symbols files, and these are different
        // between ipa builds even if nothing has changed.
        expect(differ.dartFileSetDiff(fileSetDiff), isNotEmpty);

        // Native changes will always be present, even if no Swift or Obj-C
        // files have changed
        expect(differ.nativeFileSetDiff(fileSetDiff), isNotEmpty);
      });

      test('detects dart changes', () {
        final fileSetDiff =
            differ.changedFiles(baseIpaBath, changedDartIpaBath);
        expect(differ.assetsFileSetDiff(fileSetDiff), isEmpty);
        expect(differ.dartFileSetDiff(fileSetDiff), isNotEmpty);

        // Native changes will always be present, even if no Swift or Obj-C
        // files have changed
        expect(differ.nativeFileSetDiff(fileSetDiff), isNotEmpty);
      });
    });
  });
}

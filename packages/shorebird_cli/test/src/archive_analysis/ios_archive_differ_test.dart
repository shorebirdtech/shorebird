import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:test/test.dart';

void main() {
  final ipaFixturesBasePath = p.join('test', 'fixtures', 'ipas');
  final baseIpaPath = p.join(ipaFixturesBasePath, 'base.ipa');
  final changedAssetIpaPath = p.join(ipaFixturesBasePath, 'asset_changes.ipa');
  final changedDartIpaPath = p.join(ipaFixturesBasePath, 'dart_changes.ipa');
  final changedSwiftIpaPath = p.join(ipaFixturesBasePath, 'swift_changes.ipa');

  final xcframeworkFixturesBasePath = p.join(
    'test',
    'fixtures',
    'xcframeworks',
  );
  final baseXcframeworkPath =
      p.join(xcframeworkFixturesBasePath, 'base.xcframework.zip');
  final changedAssetXcframeworkPath =
      p.join(xcframeworkFixturesBasePath, 'changed_asset.xcframework.zip');
  final changedDartXcframeworkPath =
      p.join(xcframeworkFixturesBasePath, 'changed_dart.xcframework.zip');

  group(
    IosArchiveDiffer,
    () {
      late IosArchiveDiffer differ;

      setUp(() {
        differ = IosArchiveDiffer();
      });

      group('ipa', () {
        group('changedPaths', () {
          test('finds no differences between the same ipa', () {
            expect(
              differ.changedFiles(baseIpaPath, baseIpaPath),
              isEmpty,
            );
          });

          test('finds differences between two different ipas', () {
            expect(
              differ
                  .changedFiles(baseIpaPath, changedAssetIpaPath)
                  .changedPaths,
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

        group('containsPotentiallyBreakingAssetDiffs', () {
          test('returns true if a file in flutter_assets has changed', () {
            final fileSetDiff = differ.changedFiles(
              baseIpaPath,
              changedAssetIpaPath,
            );
            expect(
              differ.containsPotentiallyBreakingAssetDiffs(fileSetDiff),
              isTrue,
            );
          });

          test('returns false if no files in flutter_assets has changed', () {
            final fileSetDiff = differ.changedFiles(
              baseIpaPath,
              changedDartIpaPath,
            );
            expect(
              differ.containsPotentiallyBreakingAssetDiffs(fileSetDiff),
              isFalse,
            );
          });
        });

        group('containsPotentiallyBreakingNativeDiffs', () {
          test('returns true if Swift files have been changed', () {
            final fileSetDiff = differ.changedFiles(
              baseIpaPath,
              changedSwiftIpaPath,
            );
            expect(
              differ.containsPotentiallyBreakingNativeDiffs(fileSetDiff),
              isTrue,
            );
          });

          test('returns false if Swift files have not been changed', () {
            final fileSetDiff = differ.changedFiles(
              baseIpaPath,
              changedAssetIpaPath,
            );
            expect(
              differ.containsPotentiallyBreakingNativeDiffs(fileSetDiff),
              isFalse,
            );
          });
        });
      });

      group('xcframework', () {
        group('changedPaths', () {
          test('finds no differences between the same zipped xcframeworks', () {
            expect(
              differ.changedFiles(baseXcframeworkPath, baseXcframeworkPath),
              isEmpty,
            );
          });

          test('finds differences between two differed zipped xcframeworks',
              () {
            expect(
              differ
                  .changedFiles(
                      baseXcframeworkPath, changedAssetXcframeworkPath)
                  .changedPaths,
              {
                'ios-arm64_x86_64-simulator/App.framework/_CodeSignature/CodeResources',
                'ios-arm64_x86_64-simulator/App.framework/flutter_assets/assets/asset.json',
                'ios-arm64/App.framework/_CodeSignature/CodeResources',
                'ios-arm64/App.framework/flutter_assets/assets/asset.json'
              },
            );
          });
        });

        group('changedFiles', () {
          test('detects asset changes', () {
            final fileSetDiff = differ.changedFiles(
              baseXcframeworkPath,
              changedAssetXcframeworkPath,
            );
            expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
            expect(differ.dartFileSetDiff(fileSetDiff), isEmpty);
            expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
          });

          test('detects dart changes', () {
            final fileSetDiff = differ.changedFiles(
              baseXcframeworkPath,
              changedDartXcframeworkPath,
            );
            expect(differ.assetsFileSetDiff(fileSetDiff), isEmpty);
            expect(differ.dartFileSetDiff(fileSetDiff), isNotEmpty);
            expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
          });
        });
      });
    },
    // These tests rely on the presence of the `codesign` executable, which is
    // only present on macOS.
    skip: !platform.isMacOS,
  );
}

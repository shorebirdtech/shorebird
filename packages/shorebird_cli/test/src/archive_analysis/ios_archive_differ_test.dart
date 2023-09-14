import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:test/test.dart';

void main() {
  final xcarchiveFixturesBasePath = p.join('test', 'fixtures', 'xcarchives');
  final baseIpaPath = p.join(
    xcarchiveFixturesBasePath,
    'base.xcarchive.zip',
  );
  final changedAssetIpaPath = p.join(
    xcarchiveFixturesBasePath,
    'changed_asset.xcarchive.zip',
  );
  final changedDartIpaPath = p.join(
    xcarchiveFixturesBasePath,
    'changed_dart.xcarchive.zip',
  );
  final changedSwiftIpaPath = p.join(
    xcarchiveFixturesBasePath,
    'changed_swift.xcarchive.zip',
  );

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

      group('appRegex', () {
        test('identifies Runner.app/Runner as an app file', () {
          expect(
            IosArchiveDiffer.appRegex.hasMatch(
              'Products/Applications/Runner.app/Runner',
            ),
            isTrue,
          );
        });

        test('does not identify Runner.app/Assets.car as an app file', () {
          expect(
            IosArchiveDiffer.appRegex.hasMatch(
              'Products/Applications/Runner.app/Assets.car',
            ),
            isFalse,
          );
        });
      });

      group('xcarchive', () {
        group('changedPaths', () {
          test('finds no differences between the same xcarchive', () {
            expect(
              differ.changedFiles(baseIpaPath, baseIpaPath),
              isEmpty,
            );
          });

          test('finds differences between two different xcarchives', () {
            final fileSetDiff = differ.changedFiles(
              baseIpaPath,
              changedAssetIpaPath,
            );
            if (platform.isMacOS) {
              expect(
                fileSetDiff.changedPaths,
                {
                  'Products/Applications/Runner.app/Frameworks/App.framework/_CodeSignature/CodeResources',
                  'Products/Applications/Runner.app/Frameworks/App.framework/flutter_assets/assets/asset.json',
                  'Info.plist',
                },
              );
            } else {
              expect(
                fileSetDiff.changedPaths,
                {
                  'Products/Applications/Runner.app/Frameworks/App.framework/_CodeSignature/CodeResources',
                  'Products/Applications/Runner.app/Frameworks/App.framework/App',
                  'Products/Applications/Runner.app/Frameworks/App.framework/flutter_assets/assets/asset.json',
                  'Info.plist',
                },
              );
            }
          });
        });

        group('changedFiles', () {
          test('detects asset changes', () {
            final fileSetDiff =
                differ.changedFiles(baseIpaPath, changedAssetIpaPath);
            expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
            expect(
              differ.dartFileSetDiff(fileSetDiff),
              platform.isMacOS ? isEmpty : isNotEmpty,
            );
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
            final fileSetDiff = differ.changedFiles(
              baseXcframeworkPath,
              changedAssetXcframeworkPath,
            );
            if (platform.isMacOS) {
              expect(
                fileSetDiff.changedPaths,
                {
                  'ios-arm64_x86_64-simulator/App.framework/_CodeSignature/CodeResources',
                  'ios-arm64_x86_64-simulator/App.framework/flutter_assets/assets/asset.json',
                  'ios-arm64/App.framework/_CodeSignature/CodeResources',
                  'ios-arm64/App.framework/flutter_assets/assets/asset.json',
                },
              );
            } else {
              expect(
                fileSetDiff.changedPaths,
                {
                  'ios-arm64_x86_64-simulator/App.framework/_CodeSignature/CodeResources',
                  'ios-arm64_x86_64-simulator/App.framework/App',
                  'ios-arm64_x86_64-simulator/App.framework/flutter_assets/assets/asset.json',
                  'ios-arm64/App.framework/_CodeSignature/CodeResources',
                  'ios-arm64/App.framework/App',
                  'ios-arm64/App.framework/flutter_assets/assets/asset.json',
                },
              );
            }
          });
        });

        group('changedFiles', () {
          test('detects asset changes', () {
            final fileSetDiff = differ.changedFiles(
              baseXcframeworkPath,
              changedAssetXcframeworkPath,
            );
            expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
            expect(
              differ.dartFileSetDiff(fileSetDiff),
              platform.isMacOS ? isEmpty : isNotEmpty,
            );
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
  );
}

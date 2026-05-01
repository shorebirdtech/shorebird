// cspell:words xcarchive xcarchives xcframeworks xcframework actool assetutil
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  final xcarchiveFixturesBasePath = p.join('test', 'fixtures', 'xcarchives');
  final baseIpaPath = p.join(xcarchiveFixturesBasePath, 'base.xcarchive.zip');
  final baseChangedUuidPath = p.join(
    xcarchiveFixturesBasePath,
    'base_changed_uuid.xcarchive.zip',
  );
  final changedAssetXcarchivePath = p.join(
    xcarchiveFixturesBasePath,
    'changed_asset.xcarchive.zip',
  );
  final changedCarXcarchivePath = p.join(
    xcarchiveFixturesBasePath,
    'changed_assets_car.xcarchive.zip',
  );
  final changedDartXcarchivePath = p.join(
    xcarchiveFixturesBasePath,
    'changed_dart.xcarchive.zip',
  );
  final changedSwiftXcarchivePath = p.join(
    xcarchiveFixturesBasePath,
    'changed_swift.xcarchive.zip',
  );

  final xcframeworkFixturesBasePath = p.join(
    'test',
    'fixtures',
    'xcframeworks',
  );
  final baseXcframeworkPath = p.join(
    xcframeworkFixturesBasePath,
    'base.xcframework.zip',
  );
  final changedAssetXcframeworkPath = p.join(
    xcframeworkFixturesBasePath,
    'changed_asset.xcframework.zip',
  );
  final changedDartXcframeworkPath = p.join(
    xcframeworkFixturesBasePath,
    'changed_dart.xcframework.zip',
  );

  group(AppleArchiveDiffer, () {
    late Diff diff;
    late AppleArchiveDiffer differ;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {diffRef.overrideWith(() => diff)},
      );
    }

    setUpAll(() {
      registerFallbackValue(DiffColorMode.always);
    });

    setUp(() {
      diff = MockDiff();
      differ = const AppleArchiveDiffer();
    });

    group('appRegex', () {
      test('identifies Runner.app/Runner as an app file', () {
        expect(
          AppleArchiveDiffer.xcFrameworkAppRegex.hasMatch(
            'Products/Applications/Runner.app/Runner',
          ),
          isTrue,
        );
      });

      test('does not identify Runner.app/Assets.car as an app file', () {
        expect(
          AppleArchiveDiffer.xcFrameworkAppRegex.hasMatch(
            'Products/Applications/Runner.app/Assets.car',
          ),
          isFalse,
        );
      });
    });

    group('sanitizeCarJson', () {
      test('strips Timestamp lines', () {
        final input = [
          '{',
          '  "Timestamp" : 1234567890',
          '  "Name" : "AppIcon"',
          '}',
        ];
        expect(
          AppleArchiveDiffer.sanitizeCarJson(input),
          '{\n  "Name" : "AppIcon"\n}',
        );
      });

      test('hashes equivalently when only layered icon UUIDs differ', () {
        // actool generates a fresh UUID for each build of an iOS 18
        // layered icon (.icon) bundle, which appears in the
        // RenditionName/Name fields of the assetutil --info output.
        const uuidA = '1FB87FB1-9D9F-4F60-B3C3-6E63B0B0E3DD';
        const uuidB = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE';
        final buildA = [
          '  "Name" : "AppIcon-$uuidA"',
          '  "RenditionName" : "AppIcon-$uuidA.png"',
        ];
        final buildB = [
          '  "Name" : "AppIcon-$uuidB"',
          '  "RenditionName" : "AppIcon-$uuidB.png"',
        ];
        expect(
          AppleArchiveDiffer.sanitizeCarJson(buildA),
          AppleArchiveDiffer.sanitizeCarJson(buildB),
        );
      });

      test('still detects rendition name changes that are not just UUIDs', () {
        const uuid = '1FB87FB1-9D9F-4F60-B3C3-6E63B0B0E3DD';
        final before = ['  "RenditionName" : "AppIcon-$uuid.png"'];
        final after = ['  "RenditionName" : "AppIconDark-$uuid.png"'];
        expect(
          AppleArchiveDiffer.sanitizeCarJson(before),
          isNot(AppleArchiveDiffer.sanitizeCarJson(after)),
        );
      });
    });

    group('xcarchive', () {
      group('changedPaths', () {
        test('finds no differences between the same xcarchive', () async {
          expect(await differ.changedFiles(baseIpaPath, baseIpaPath), isEmpty);
        });

        test('finds no differences when only Mach-O UUID differs', () async {
          final fileSetDiff = await differ.changedFiles(
            baseIpaPath,
            baseChangedUuidPath,
          );
          expect(fileSetDiff, isEmpty);
        });

        test('finds differences between two different xcarchives', () async {
          final fileSetDiff = await differ.changedFiles(
            baseIpaPath,
            changedAssetXcarchivePath,
          );
          if (platform.isMacOS) {
            expect(fileSetDiff.changedPaths, {
              'Products/Applications/Runner.app/Frameworks/App.framework/_CodeSignature/CodeResources',
              'Products/Applications/Runner.app/Frameworks/App.framework/flutter_assets/NOTICES.Z',
              'Products/Applications/Runner.app/Frameworks/App.framework/flutter_assets/assets/asset.json',
              'Info.plist',
            });
          } else {
            expect(fileSetDiff.changedPaths, {
              'Products/Applications/Runner.app/Frameworks/App.framework/_CodeSignature/CodeResources',
              'Products/Applications/Runner.app/Frameworks/App.framework/App',
              'Products/Applications/Runner.app/Frameworks/App.framework/flutter_assets/assets/asset.json',
              'Info.plist',
            });
          }
        });
      });

      group('changedFiles', () {
        test('detects asset changes', () async {
          final fileSetDiff = await differ.changedFiles(
            baseIpaPath,
            changedAssetXcarchivePath,
          );
          expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
          expect(
            differ.dartFileSetDiff(fileSetDiff),
            platform.isMacOS ? isEmpty : isNotEmpty,
          );
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });

        test('detects dart changes', () async {
          final fileSetDiff = await differ.changedFiles(
            baseIpaPath,
            changedDartXcarchivePath,
          );
          expect(differ.assetsFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });

        test('detects swift changes', () async {
          final fileSetDiff = await differ.changedFiles(
            baseIpaPath,
            changedSwiftXcarchivePath,
          );
          expect(differ.assetsFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isNotEmpty);
        });
      });

      group('containsPotentiallyBreakingAssetDiffs', () {
        test('returns true if a file in flutter_assets has changed', () async {
          final fileSetDiff = await differ.changedFiles(
            baseIpaPath,
            changedAssetXcarchivePath,
          );
          expect(
            differ.containsPotentiallyBreakingAssetDiffs(fileSetDiff),
            isTrue,
          );
        });

        test(
          'returns false if no files in flutter_assets has changed',
          () async {
            final fileSetDiff = await differ.changedFiles(
              baseIpaPath,
              changedDartXcarchivePath,
            );
            expect(
              differ.containsPotentiallyBreakingAssetDiffs(fileSetDiff),
              isFalse,
            );
          },
        );
      });

      group('containsPotentiallyBreakingNativeDiffs', () {
        test('returns true if Swift files have been changed', () async {
          final fileSetDiff = await differ.changedFiles(
            baseIpaPath,
            changedSwiftXcarchivePath,
          );
          expect(
            differ.containsPotentiallyBreakingNativeDiffs(fileSetDiff),
            isTrue,
          );
        });

        test('returns false if Swift files have not been changed', () async {
          final fileSetDiff = await differ.changedFiles(
            baseIpaPath,
            changedAssetXcarchivePath,
          );
          expect(
            differ.containsPotentiallyBreakingNativeDiffs(fileSetDiff),
            isFalse,
          );
        });
      });

      group('availableAssetDiffs', () {
        group('when a car file has changed', () {
          const diffOutput = 'diff output';

          setUp(() {
            when(
              () => diff.run(
                any(),
                any(),
                colorMode: any(named: 'colorMode'),
                unified: any(named: 'unified'),
              ),
            ).thenAnswer(
              (_) async => const ShorebirdProcessResult(
                exitCode: 1,
                stdout: diffOutput,
                stderr: '',
              ),
            );
          });

          test('shows asset diffs', () async {
            final fileSetDiff = await differ.changedFiles(
              baseIpaPath,
              changedCarXcarchivePath,
            );
            await runWithOverrides(() async {
              expect(
                await differ.availableAssetDiffs(
                  fileSetDiff: fileSetDiff,
                  oldArchivePath: baseIpaPath,
                  newArchivePath: changedCarXcarchivePath,
                ),
                equals(diffOutput),
              );
            });
          });
        });

        group('when no car files have changed', () {
          test('shows no asset diffs', () async {
            final fileSetDiff = await differ.changedFiles(
              baseIpaPath,
              changedDartXcarchivePath,
            );
            await runWithOverrides(() async {
              expect(
                await differ.availableAssetDiffs(
                  fileSetDiff: fileSetDiff,
                  oldArchivePath: baseIpaPath,
                  newArchivePath: changedDartXcarchivePath,
                ),
                isEmpty,
              );
            });
          });
        });
      });
    });

    group('xcframework', () {
      group('changedPaths', () {
        test(
          'finds no differences between the same zipped xcframeworks',
          () async {
            expect(
              await differ.changedFiles(
                baseXcframeworkPath,
                baseXcframeworkPath,
              ),
              isEmpty,
            );
          },
        );

        test('finds differences between two '
            'differed zipped xcframeworks', () async {
          final fileSetDiff = await differ.changedFiles(
            baseXcframeworkPath,
            changedAssetXcframeworkPath,
          );
          if (platform.isMacOS) {
            expect(fileSetDiff.changedPaths, {
              'ios-arm64_x86_64-simulator/App.framework/_CodeSignature/CodeResources',
              'ios-arm64_x86_64-simulator/App.framework/flutter_assets/assets/asset.json',
              'ios-arm64/App.framework/_CodeSignature/CodeResources',
              'ios-arm64/App.framework/flutter_assets/assets/asset.json',
            });
          } else {
            expect(fileSetDiff.changedPaths, {
              'ios-arm64_x86_64-simulator/App.framework/_CodeSignature/CodeResources',
              'ios-arm64_x86_64-simulator/App.framework/App',
              'ios-arm64_x86_64-simulator/App.framework/flutter_assets/assets/asset.json',
              'ios-arm64/App.framework/_CodeSignature/CodeResources',
              'ios-arm64/App.framework/App',
              'ios-arm64/App.framework/flutter_assets/assets/asset.json',
            });
          }
        });
      });

      group('changedFiles', () {
        test('detects asset changes', () async {
          final fileSetDiff = await differ.changedFiles(
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

        test('detects dart changes', () async {
          final fileSetDiff = await differ.changedFiles(
            baseXcframeworkPath,
            changedDartXcframeworkPath,
          );
          expect(differ.assetsFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });
      });
    });
  }, testOn: 'mac-os');
}

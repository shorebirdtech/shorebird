// cspell:words xcarchive xcarchives xcframeworks xcframework actool assetutil
import 'dart:convert';
import 'dart:io';

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
      test('strips Timestamp', () {
        const withTimestamp = '''
[{"Timestamp" : 1234567890, "Name" : "AppIcon"}]''';
        const withoutTimestamp = '[{"Name" : "AppIcon"}]';
        expect(
          AppleArchiveDiffer.sanitizeCarJson(withTimestamp),
          AppleArchiveDiffer.sanitizeCarJson(withoutTimestamp),
        );
      });

      test('hashes equivalently when only layered icon UUIDs differ', () {
        // actool generates a fresh UUID for each build of an iOS 18
        // layered icon (.icon) bundle, which appears in the
        // RenditionName/Name fields of the assetutil --info output.
        const uuidA = '1FB87FB1-9D9F-4F60-B3C3-6E63B0B0E3DD';
        const uuidB = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE';
        const buildA = '''
[{"Name" : "AppIcon-$uuidA", "RenditionName" : "AppIcon-$uuidA.png"}]''';
        const buildB = '''
[{"Name" : "AppIcon-$uuidB", "RenditionName" : "AppIcon-$uuidB.png"}]''';
        expect(
          AppleArchiveDiffer.sanitizeCarJson(buildA),
          AppleArchiveDiffer.sanitizeCarJson(buildB),
        );
      });

      test('still detects rendition name changes that are not just UUIDs', () {
        const uuid = '1FB87FB1-9D9F-4F60-B3C3-6E63B0B0E3DD';
        const before = '[{"RenditionName" : "AppIcon-$uuid.png"}]';
        const after = '[{"RenditionName" : "AppIconDark-$uuid.png"}]';
        expect(
          AppleArchiveDiffer.sanitizeCarJson(before),
          isNot(AppleArchiveDiffer.sanitizeCarJson(after)),
        );
      });

      test('keeps keys that differ only by UUID distinct', () {
        const uuidA = '1FB87FB1-9D9F-4F60-B3C3-6E63B0B0E3DD';
        const uuidB = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE';
        const both = '[{"Icon-$uuidA" : 1, "Icon-$uuidB" : 2}]';
        // Matches what `both` would reduce to if the keys were normalized
        // and collapsed, so this fails rather than passes if that returns.
        const one = '[{"Icon-$uuidB" : 2}]';
        expect(
          AppleArchiveDiffer.sanitizeCarJson(both),
          isNot(AppleArchiveDiffer.sanitizeCarJson(one)),
        );
      });

      test('is insensitive to the order assetutil emits fields in', () {
        const orderA = '[{"Name" : "AppIcon", "Scale" : 1}]';
        const orderB = '[{"Scale" : 1, "Name" : "AppIcon"}]';
        expect(
          AppleArchiveDiffer.sanitizeCarJson(orderA),
          AppleArchiveDiffer.sanitizeCarJson(orderB),
        );
      });

      test('hashes unparseable output verbatim rather than throwing', () {
        const notJson = 'assetutil: unable to read archive';
        expect(AppleArchiveDiffer.sanitizeCarJson(notJson), notJson);
      });

      group('layered icon renditions', () {
        final fixturesPath = p.join('test', 'fixtures', 'assetutil');
        String readFixture(String name) =>
            File(p.join(fixturesPath, name)).readAsStringSync();

        // Matched independently of the production pattern, so that a test
        // targeting a generated rendition cannot be fooled into targeting
        // something else by the very regex it is checking.
        final generatedName = RegExp(
          '_[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-'
          r'[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}-\d+-[0-9A-Fa-f]+',
        );

        /// Rewrites [key] on the first rendition carrying a generated name, so
        /// the edit lands on an entry whose `SHA1Digest` was stripped rather
        /// than one still compared on its digest alone.
        String editGeneratedRendition(
          String contents,
          String key,
          Object? value,
        ) {
          final entries = jsonDecode(contents) as List<dynamic>;
          final target = entries.cast<Map<String, dynamic>>().firstWhere(
            (entry) =>
                entry['RenditionName'] is String &&
                generatedName.hasMatch(entry['RenditionName'] as String) &&
                entry.containsKey('SHA1Digest') &&
                entry.containsKey(key),
          );
          target[key] = value;
          return jsonEncode(entries);
        }

        late String buildA;
        late String buildB;

        setUp(() {
          buildA = readFixture('layered_icon_build_a.json');
          buildB = readFixture('layered_icon_build_b.json');
        });

        test('two builds of an unchanged icon sanitize identically', () {
          // These two dumps differ only in Timestamp, RenditionName and
          // SHA1Digest, all regenerated by actool. Treating that as an asset
          // change is what blocks a patch for a user who changed nothing.
          expect(buildA, isNot(buildB));
          expect(
            AppleArchiveDiffer.sanitizeCarJson(buildA),
            AppleArchiveDiffer.sanitizeCarJson(buildB),
          );
        });

        test('still detects an icon whose byte count changed', () {
          final edited = editGeneratedRendition(buildA, 'SizeOnDisk', 1);
          expect(
            AppleArchiveDiffer.sanitizeCarJson(buildA),
            isNot(AppleArchiveDiffer.sanitizeCarJson(edited)),
          );
        });

        test('still detects an icon whose dimensions changed', () {
          final edited = editGeneratedRendition(buildA, 'PixelWidth', 512);
          expect(
            AppleArchiveDiffer.sanitizeCarJson(buildA),
            isNot(AppleArchiveDiffer.sanitizeCarJson(edited)),
          );
        });

        test('still compares SHA1Digest on renditions actool did not '
            'generate a name for', () {
          const before =
              '[{"RenditionName" : "asset.png", "SHA1Digest" : "AAAA"}]';
          const after =
              '[{"RenditionName" : "asset.png", "SHA1Digest" : "BBBB"}]';
          expect(
            AppleArchiveDiffer.sanitizeCarJson(before),
            isNot(AppleArchiveDiffer.sanitizeCarJson(after)),
          );
        });

        test('normalizes the pid and counter, not just the uuid', () {
          // The uuid is held constant here so that the pid and counter, which
          // sit outside it and which the original fix did not cover, are the
          // only thing the two dumps disagree on.
          const uuid = '1FB87FB1-9D9F-4F60-B3C3-6E63B0B0E3DD';
          String dump(String pid, String counter) =>
              '[{"RenditionName" : "AppIcon_$uuid-$pid-$counter.png"}]';
          expect(
            AppleArchiveDiffer.sanitizeCarJson(dump('38834', '00000317C82E5')),
            AppleArchiveDiffer.sanitizeCarJson(dump('43420', '0000031A230EE')),
          );
        });
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

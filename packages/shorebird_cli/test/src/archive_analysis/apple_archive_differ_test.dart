// cspell:words xcarchive xcarchives xcframeworks xcframework actool assetutil
// cspell:words chkstk dsym dsyms linkedit lzfse methname movz plists posthog
// cspell:words tintable
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:macho/macho.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
  final xcarchiveFixturesBasePath = p.join(fixturesDirectory, 'xcarchives');
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
    fixturesDirectory,
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

      test('hashes equivalently across an Xcode toolchain bump', () {
        // The header block assetutil emits for the same unchanged catalog,
        // built before and after the Xcode 26.3 upgrade that took CoreUI
        // from 972 to 973.
        const buildA = '''
[{"AssetStorageVersion" : "Xcode 26.2 (17B123) via AssetCatalogSimulatorAgent", "Authoring Tool" : "@(#)PROGRAM:CoreThemeDefinition  PROJECT:CoreThemeDefinition-653.3  [IIO-2784.2.5.1.3]", "CoreUIVersion" : 972, "DumpToolVersion" : 918.8, "MainVersion" : "@(#)PROGRAM:CoreUI  PROJECT:CoreUI-972.1", "Platform" : "ios", "PlatformVersion" : "17.0", "SchemaVersion" : 2}]''';
        const buildB = '''
[{"AssetStorageVersion" : "Xcode 26.3 (17C529) via AssetCatalogSimulatorAgent", "Authoring Tool" : "@(#)PROGRAM:CoreThemeDefinition  PROJECT:CoreThemeDefinition-653.3  [IIO-2784.3.4]", "CoreUIVersion" : 973, "DumpToolVersion" : 918.8, "MainVersion" : "@(#)PROGRAM:CoreUI  PROJECT:CoreUI-973.1", "Platform" : "ios", "PlatformVersion" : "17.0", "SchemaVersion" : 2}]''';
        expect(
          AppleArchiveDiffer.sanitizeCarJson(buildA),
          AppleArchiveDiffer.sanitizeCarJson(buildB),
        );
      });

      test('still detects a rendition edit made under a new toolchain', () {
        const buildA = '''
[{"CoreUIVersion" : 972, "RenditionName" : "logo.png", "SizeOnDisk" : 4096}]''';
        const edited = '''
[{"CoreUIVersion" : 973, "RenditionName" : "logo.png", "SizeOnDisk" : 8192}]''';
        expect(
          AppleArchiveDiffer.sanitizeCarJson(buildA),
          isNot(AppleArchiveDiffer.sanitizeCarJson(edited)),
        );
      });

      test('still detects PlatformVersion and SchemaVersion changes', () {
        const before = '[{"PlatformVersion" : "17.0", "SchemaVersion" : 2}]';
        const afterPlatform =
            '[{"PlatformVersion" : "18.0", "SchemaVersion" : 2}]';
        const afterSchema =
            '[{"PlatformVersion" : "17.0", "SchemaVersion" : 3}]';
        expect(
          AppleArchiveDiffer.sanitizeCarJson(before),
          isNot(AppleArchiveDiffer.sanitizeCarJson(afterPlatform)),
        );
        expect(
          AppleArchiveDiffer.sanitizeCarJson(before),
          isNot(AppleArchiveDiffer.sanitizeCarJson(afterSchema)),
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

      test('hashes non-JSON output verbatim rather than throwing', () {
        const notJson = 'assetutil: unable to read archive';
        expect(AppleArchiveDiffer.sanitizeCarJson(notJson), notJson);
      });

      group('layered icon renditions', () {
        final fixturesPath = p.join(fixturesDirectory, 'assetutil');
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

      group(
        'Xcode 16+ appearance renditions and 3rd-party bundle Assets.car',
        () {
          const uuidA = '1FB87FB1-9D9F-4F60-B3C3-6E63B0B0E3DD';
          const uuidB = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE';

          String appearanceCarJson({
            required String uuid,
            required String sha1Digest,
            String appearance = 'UIAppearanceAny',
            int sizeOnDisk = 4096,
            String encoding = 'ARGB',
            String compression = 'lzfse',
            int width = 1024,
            int height = 1024,
          }) => jsonEncode([
            {
              'AssetType': 'Icon Image',
              'Appearance': appearance,
              'Compression': compression,
              'Encoding': encoding,
              'Name': 'AppIcon',
              'PixelHeight': height,
              'PixelWidth': width,
              'RenditionName':
                  'AppIcon${width}x${height}_${appearance}_$uuid.png',
              'SHA1Digest': sha1Digest,
              'SizeOnDisk': sizeOnDisk,
            },
          ]);

          test('strips UUID and SHA1Digest on UIAppearanceAny, '
              'UIAppearanceDark, and ISAppearanceTintable renditions when '
              'dimensions and size match', () {
            for (final appearance in [
              'UIAppearanceAny',
              'UIAppearanceDark',
              'ISAppearanceTintable',
            ]) {
              final buildA = appearanceCarJson(
                uuid: uuidA,
                sha1Digest: '1111111111111111111111111111111111111111',
                appearance: appearance,
              );
              final buildB = appearanceCarJson(
                uuid: uuidB,
                sha1Digest: '2222222222222222222222222222222222222222',
                appearance: appearance,
              );
              expect(
                AppleArchiveDiffer.sanitizeCarJson(buildA),
                equals(AppleArchiveDiffer.sanitizeCarJson(buildB)),
              );
            }
          });

          test('keeps different appearance variants distinct', () {
            final anyVariant = appearanceCarJson(
              uuid: uuidA,
              sha1Digest: '1111111111111111111111111111111111111111',
            );
            final darkVariant = appearanceCarJson(
              uuid: uuidA,
              sha1Digest: '1111111111111111111111111111111111111111',
              appearance: 'UIAppearanceDark',
            );
            expect(
              AppleArchiveDiffer.sanitizeCarJson(anyVariant),
              isNot(equals(AppleArchiveDiffer.sanitizeCarJson(darkVariant))),
            );
          });

          test(
            'detects a 1-byte SizeOnDisk change on an appearance rendition',
            () {
              final buildA = appearanceCarJson(
                uuid: uuidA,
                sha1Digest: '1111111111111111111111111111111111111111',
              );
              final buildB = appearanceCarJson(
                uuid: uuidB,
                sha1Digest: '2222222222222222222222222222222222222222',
                sizeOnDisk: 4097,
              );
              expect(
                AppleArchiveDiffer.sanitizeCarJson(buildA),
                isNot(equals(AppleArchiveDiffer.sanitizeCarJson(buildB))),
              );
            },
          );

          test('detects a dimension change on an appearance rendition', () {
            final buildA = appearanceCarJson(
              uuid: uuidA,
              sha1Digest: '1111111111111111111111111111111111111111',
            );
            final buildB = appearanceCarJson(
              uuid: uuidB,
              sha1Digest: '2222222222222222222222222222222222222222',
              width: 512,
            );
            expect(
              AppleArchiveDiffer.sanitizeCarJson(buildA),
              isNot(equals(AppleArchiveDiffer.sanitizeCarJson(buildB))),
            );
          });
        },
      );
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

        test('leaves no temporary files behind', () async {
          final expected = await differ.changedFiles(
            baseIpaPath,
            changedCarXcarchivePath,
          );
          final systemTemp = createSystemTemp();
          late FileSetDiff fileSetDiff;
          await runWithSystemTemp(systemTemp, () async {
            fileSetDiff = await differ.changedFiles(
              baseIpaPath,
              changedCarXcarchivePath,
            );
          });
          expect(fileSetDiff.changedPaths, equals(expected.changedPaths));
          expect(systemTemp.listSync(), isEmpty);
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

          test('leaves no temporary files behind', () async {
            final fileSetDiff = await differ.changedFiles(
              baseIpaPath,
              changedCarXcarchivePath,
            );
            final systemTemp = createSystemTemp();
            await runWithSystemTemp(
              systemTemp,
              () => runWithOverrides(
                () => differ.availableAssetDiffs(
                  fileSetDiff: fileSetDiff,
                  oldArchivePath: baseIpaPath,
                  newArchivePath: changedCarXcarchivePath,
                ),
              ),
            );
            expect(systemTemp.listSync(), isEmpty);
          });

          test('releases the archives it reads', () async {
            // Windows refuses to delete a file that is still open, so this
            // fails there if the differ leaks a file handle.
            final fileSetDiff = await differ.changedFiles(
              baseIpaPath,
              changedCarXcarchivePath,
            );
            final tempDir = Directory.systemTemp.createTempSync();
            final oldPath = p.join(tempDir.path, 'old.zip');
            final newPath = p.join(tempDir.path, 'new.zip');
            File(baseIpaPath).copySync(oldPath);
            File(changedCarXcarchivePath).copySync(newPath);

            await runWithOverrides(
              () => differ.availableAssetDiffs(
                fileSetDiff: fileSetDiff,
                oldArchivePath: oldPath,
                newArchivePath: newPath,
              ),
            );

            File(oldPath).deleteSync();
            File(newPath).deleteSync();
            tempDir.deleteSync(recursive: true);
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
    }, testOn: 'mac-os');

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

    group('semantic Mach-O and embedded framework diffing', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('apple_macho_diff_');
      });

      tearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      String writeSyntheticZip(String fileName, Map<String, List<int>> files) {
        final archive = Archive();
        for (final entry in files.entries) {
          archive.addFile(
            ArchiveFile(entry.key, entry.value.length, entry.value),
          );
        }
        final path = p.join(tempDir.path, fileName);
        File(path).writeAsBytesSync(ZipEncoder().encode(archive));
        return path;
      }

      Uint8List xmlPlist({
        String? shortVersion = '1.0.0',
        String? buildNumber = '1',
        Map<String, String> extra = const {},
      }) {
        final buffer = StringBuffer('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
''');
        if (shortVersion != null) {
          buffer.writeln(
            '  <key>CFBundleShortVersionString</key><string>$shortVersion</string>',
          );
        }
        if (buildNumber != null) {
          buffer.writeln(
            '  <key>CFBundleVersion</key><string>$buildNumber</string>',
          );
        }
        for (final entry in extra.entries) {
          buffer.writeln(
            '  <key>${entry.key}</key><string>${entry.value}</string>',
          );
        }
        buffer.write('</dict>\n</plist>\n');
        return Uint8List.fromList(utf8.encode(buffer.toString()));
      }

      Uint8List binaryPlist({
        required String shortVersion,
        String? buildNumber,
      }) {
        final data = PropertyListSerialization.dataWithPropertyList({
          'CFBundleShortVersionString': shortVersion,
          'CFBundleVersion': ?buildNumber,
        });
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }

      test('isNativeFilePath recognizes app executables, macOS binaries, '
          'and non-Flutter embedded frameworks', () {
        expect(
          differ.isNativeFilePath('Products/Applications/Runner.app/Runner'),
          isTrue,
        );
        expect(differ.isNativeFilePath('Contents/MacOS/Runner'), isTrue);
        expect(
          differ.isNativeFilePath(
            'Products/Applications/Runner.app/Frameworks/PostHog.framework/PostHog',
          ),
          isTrue,
        );
        expect(
          differ.isNativeFilePath(
            'Contents/Frameworks/PostHog.framework/Versions/A/PostHog',
          ),
          isTrue,
        );
        expect(
          differ.isNativeFilePath(
            'Products/Applications/Runner.app/Frameworks/PostHog.framework/Info.plist',
          ),
          isTrue,
        );
        expect(
          differ.isNativeFilePath(
            'Products/Applications/Runner.app/Frameworks/App.framework/App',
          ),
          isFalse,
        );
        expect(
          differ.isNativeFilePath(
            'Products/Applications/Runner.app/Frameworks/Flutter.framework/Flutter',
          ),
          isFalse,
        );
        expect(
          differ.isNativeFilePath(
            'Products/Applications/Runner.app/Frameworks/ShorebirdFlutter.framework/ShorebirdFlutter',
          ),
          isFalse,
        );
        expect(
          differ.isNativeFilePath(
            'Products/Applications/Runner.app/Frameworks/App.framework/Info.plist',
          ),
          isFalse,
        );
        expect(
          differ.isNativeFilePath(
            'Products/Applications/Runner.app/Frameworks/PostHog.framework/OtherFile',
          ),
          isFalse,
        );
      });

      test('suppresses safe Mach-O differences (LC_UUID, __LINKEDIT padding, '
          'and unused ___chkstk_darwin)', () async {
        const runnerPath = 'Products/Applications/Runner.app/Runner';
        const frameworkPath =
            'Products/Applications/Runner.app/Frameworks/PostHog.framework/PostHog';
        const plistPath =
            'Products/Applications/Runner.app/Frameworks/PostHog.framework/Info.plist';

        final oldRunner = MachOBuilder.buildThin(
          uuid: MachOBuilder.defaultUuid,
          textInstructions: [Arm64Encoder.movz(0, 42), Arm64Encoder.ret()],
          symbols: const [MachOSymbolSpec(name: '_main')],
        );
        final newRunner = MachOBuilder.buildThin(
          uuid: MachOBuilder.alternateUuid,
          textInstructions: [Arm64Encoder.movz(0, 42), Arm64Encoder.ret()],
          symbols: const [
            MachOSymbolSpec(name: '_main'),
            MachOSymbolSpec.undefined('___chkstk_darwin'),
          ],
          linkeditTrailingPadding: Uint8List.fromList([
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
          ]),
        );

        final frameworkBin = MachOBuilder.buildThin(
          fileType: MachOFileType.dylib,
          textInstructions: [Arm64Encoder.movz(0, 1), Arm64Encoder.ret()],
        );

        final oldZip = writeSyntheticZip('old_safe.zip', {
          runnerPath: oldRunner,
          frameworkPath: frameworkBin,
          plistPath: xmlPlist(
            shortVersion: '3.71.6',
            extra: {'BuildMachineOSBuild': '23F79'},
          ),
        });
        final newZip = writeSyntheticZip('new_safe.zip', {
          runnerPath: newRunner,
          frameworkPath: frameworkBin,
          // Info.plist changed a non-version key while
          // CFBundleShortVersionString and CFBundleVersion are identical.
          plistPath: xmlPlist(
            shortVersion: '3.71.6',
            extra: {'BuildMachineOSBuild': '24A335'},
          ),
        });

        final diff = await differ.changedFiles(oldZip, newZip);
        expect(differ.containsPotentiallyBreakingNativeDiffs(diff), isFalse);
        expect(diff.machODiffResults, isEmpty);
        expect(diff.frameworkVersionChanges, isEmpty);
      });

      test('flags breaking Mach-O instruction, selector, and framework version '
          'changes with dSYM function resolution', () async {
        const runnerPath = 'Products/Applications/Runner.app/Runner';
        const dsymPath =
            'dSYMs/Runner.app.dSYM/Contents/Resources/DWARF/Runner';
        const posthogBinPath =
            'Products/Applications/Runner.app/Frameworks/PostHog.framework/PostHog';
        const posthogPlistPath =
            'Products/Applications/Runner.app/Frameworks/PostHog.framework/Info.plist';
        const sentryPlistPath =
            'Products/Applications/Runner.app/Frameworks/Sentry.framework/Info.plist';

        final oldRunner = MachOBuilder.buildThin(
          textInstructions: [Arm64Encoder.movz(0, 1), Arm64Encoder.ret()],
          functionStartOffsets: const [0],
        );
        final newRunner = MachOBuilder.buildThin(
          textInstructions: [Arm64Encoder.movz(0, 2), Arm64Encoder.ret()],
          functionStartOffsets: const [0],
        );
        final dsym = MachOBuilder.buildDsym(
          textSize: 8,
          symbols: const [MachOSymbolSpec(name: '_RunnerMain')],
        );

        final oldPosthog = MachOBuilder.buildThin(
          fileType: MachOFileType.dylib,
          objcSelectors: const ['setupWithConfig:'],
        );
        final newPosthog = MachOBuilder.buildThin(
          fileType: MachOFileType.dylib,
          objcSelectors: const ['setupWithConfig:', 'captureEvent:properties:'],
        );

        final oldZip = writeSyntheticZip('old_breaking.zip', {
          runnerPath: oldRunner,
          dsymPath: dsym,
          posthogBinPath: oldPosthog,
          posthogPlistPath: xmlPlist(shortVersion: '3.71.6'),
          sentryPlistPath: binaryPlist(
            shortVersion: '8.0.0',
            buildNumber: '8.0.0',
          ),
        });
        final newZip = writeSyntheticZip('new_breaking.zip', {
          runnerPath: newRunner,
          dsymPath: dsym,
          posthogBinPath: newPosthog,
          posthogPlistPath: xmlPlist(shortVersion: '3.71.7', buildNumber: '2'),
          sentryPlistPath: xmlPlist(shortVersion: null, buildNumber: '9'),
        });

        final diff = await differ.changedFiles(oldZip, newZip);
        expect(differ.containsPotentiallyBreakingNativeDiffs(diff), isTrue);
        expect(
          diff.changedPaths,
          containsAll([runnerPath, posthogBinPath, posthogPlistPath]),
        );
        expect(
          diff.machODiffResults[runnerPath]!.describe(),
          contains('_RunnerMain'),
        );
        expect(
          diff.machODiffResults[posthogBinPath]!.describe(),
          contains('Objective-C selector added: captureEvent:properties:'),
        );
        expect(
          diff.frameworkVersionChanges,
          equals(const [
            DependencyVersionChange(
              name: 'PostHog.framework',
              oldVersion: '3.71.6+1',
              newVersion: '3.71.7+2',
            ),
            DependencyVersionChange(
              name: 'Sentry.framework',
              oldVersion: '8.0.0',
              newVersion: '9',
            ),
          ]),
        );
      });

      test('conservatively keeps malformed Mach-O binaries as breaking '
          'and ignores malformed framework Info.plists', () async {
        const runnerPath = 'Contents/MacOS/Runner';
        const plistPath =
            'Contents/Frameworks/Broken.framework/Resources/Info.plist';

        final oldZip = writeSyntheticZip('old_corrupt.zip', {
          runnerPath: Uint8List.fromList([0xcf, 0xfa, 0xed, 0xfe, 1, 2, 3]),
          plistPath: Uint8List.fromList(utf8.encode('not a valid plist')),
        });
        final newZip = writeSyntheticZip('new_corrupt.zip', {
          runnerPath: Uint8List.fromList([0xcf, 0xfa, 0xed, 0xfe, 4, 5, 6]),
          plistPath: xmlPlist(shortVersion: null, buildNumber: null),
        });

        final diff = await differ.changedFiles(oldZip, newZip);
        expect(differ.containsPotentiallyBreakingNativeDiffs(diff), isTrue);
        expect(diff.changedPaths, contains(runnerPath));
        expect(diff.changedPaths, isNot(contains(plistPath)));
        expect(diff.machODiffResults[runnerPath]!.isSafe, isFalse);
        expect(diff.frameworkVersionChanges, isEmpty);
      });
    });
  });
}

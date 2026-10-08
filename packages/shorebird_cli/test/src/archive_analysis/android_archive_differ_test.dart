import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/bundle_dependencies.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';
import 'package:test/test.dart';

import 'bundle_dependencies_helpers.dart';

void main() {
  group(AndroidArchiveDiffer, () {
    final aabFixturesBasePath = p.join('test', 'fixtures', 'aabs');
    final baseAabPath = p.join(aabFixturesBasePath, 'base.aab');
    final changedAssetAabPath = p.join(
      aabFixturesBasePath,
      'changed_asset.aab',
    );
    final changedDartAabPath = p.join(aabFixturesBasePath, 'changed_dart.aab');
    final changedKotlinAabPath = p.join(
      aabFixturesBasePath,
      'changed_kotlin.aab',
    );
    final changedDartAndAssetAabPath = p.join(
      aabFixturesBasePath,
      'changed_dart_and_asset.aab',
    );

    final aarFixturesBasePath = p.join('test', 'fixtures', 'aars');
    final baseAarPath = p.join(aarFixturesBasePath, 'base.aar');
    final changedAssetAarPath = p.join(
      aarFixturesBasePath,
      'changed_asset.aar',
    );
    final changedDartAarPath = p.join(aarFixturesBasePath, 'changed_dart.aar');
    final changedDartAndAssetAarPath = p.join(
      aarFixturesBasePath,
      'changed_dart_and_asset.aar',
    );

    late AndroidArchiveDiffer differ;

    setUp(() {
      differ = const AndroidArchiveDiffer();
    });

    group('aab', () {
      group('changedFiles', () {
        test('finds no differences between the same aab', () async {
          expect(await differ.changedFiles(baseAabPath, baseAabPath), isEmpty);
        });

        test('finds differences between two different aabs', () async {
          final fileSetDiff = await differ.changedFiles(
            baseAabPath,
            changedDartAabPath,
          );
          expect(fileSetDiff.changedPaths, {
            'BUNDLE-METADATA/com.android.tools.build.libraries/dependencies.pb',
            'base/lib/arm64-v8a/libapp.so',
            'base/lib/armeabi-v7a/libapp.so',
            'base/lib/x86_64/libapp.so',
            'META-INF/ANDROIDD.SF',
            'META-INF/ANDROIDD.RSA',
            'META-INF/MANIFEST.MF',
          });
        });

        test('filters out DEX files with only path differences', () async {
          final baseDexAabPath = p.join(
            aabFixturesBasePath,
            'base_dex_test.aab',
          );
          final pathOnlyAabPath = p.join(
            aabFixturesBasePath,
            'changed_dex_path_only.aab',
          );

          final fileSetDiff = await differ.changedFiles(
            baseDexAabPath,
            pathOnlyAabPath,
          );
          // DEX file should be filtered out since only source paths differ.
          expect(
            fileSetDiff.changedPaths.where((p) => p.endsWith('.dex')).isEmpty,
            isTrue,
          );
          expect(
            differ.containsPotentiallyBreakingNativeDiffs(fileSetDiff),
            isFalse,
          );
        });

        test('keeps DEX files with structural changes', () async {
          final baseDexAabPath = p.join(
            aabFixturesBasePath,
            'base_dex_test.aab',
          );
          final methodAddedAabPath = p.join(
            aabFixturesBasePath,
            'changed_dex_method_added.aab',
          );

          final fileSetDiff = await differ.changedFiles(
            baseDexAabPath,
            methodAddedAabPath,
          );
          // DEX file should remain since there are structural changes.
          expect(
            fileSetDiff.changedPaths
                .where((p) => p.endsWith('.dex'))
                .isNotEmpty,
            isTrue,
          );
          expect(
            differ.containsPotentiallyBreakingNativeDiffs(fileSetDiff),
            isTrue,
          );
        });
      });

      group('contentDifferences', () {
        test('detects no differences between the same aab', () async {
          expect(await differ.changedFiles(baseAabPath, baseAabPath), isEmpty);
        });

        test('detects asset changes', () async {
          final fileSetDiff = await differ.changedFiles(
            baseAabPath,
            changedAssetAabPath,
          );
          expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });

        test('detects kotlin changes', () async {
          final fileSetDiff = await differ.changedFiles(
            baseAabPath,
            changedKotlinAabPath,
          );
          expect(differ.assetsFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isNotEmpty);
          expect(
            fileSetDiff.dependencyVersionChanges,
            isEmpty,
          );
        });

        group('dependency versions', () {
          late Directory tempDir;

          setUp(() {
            tempDir = Directory.systemTemp.createTempSync();
          });

          tearDown(() {
            tempDir.deleteSync(recursive: true);
          });

          /// Copies the AAB at [path], replacing its dependency metadata with
          /// [dependencies] (or removing it, if null).
          String withDependencies(String path, Uint8List? dependencies) {
            final source = ZipDecoder().decodeBytes(
              File(path).readAsBytesSync(),
            );
            final copy = Archive();
            for (final file in source.files) {
              if (file.name == bundleDependenciesPath) continue;
              copy.addFile(ArchiveFile(file.name, file.size, file.content));
            }
            if (dependencies != null) {
              copy.addFile(
                ArchiveFile(
                  bundleDependenciesPath,
                  dependencies.length,
                  dependencies,
                ),
              );
            }
            final outPath = p.join(
              tempDir.path,
              '${copy.hashCode}_${p.basename(path)}',
            );
            File(outPath).writeAsBytesSync(ZipEncoder().encode(copy));
            return outPath;
          }

          test('reports version changes when DEX files changed', () async {
            final fileSetDiff = await differ.changedFiles(
              withDependencies(
                baseAabPath,
                appDependencies([
                  mavenLibrary('io.branch.sdk.android', 'library', '5.21.2'),
                  mavenLibrary('com.example', 'same', '1.0.0'),
                ]),
              ),
              withDependencies(
                changedKotlinAabPath,
                appDependencies([
                  mavenLibrary('io.branch.sdk.android', 'library', '5.21.3'),
                  mavenLibrary('com.example', 'same', '1.0.0'),
                ]),
              ),
            );
            expect(
              fileSetDiff.dependencyVersionChanges,
              const [
                DependencyVersionChange(
                  name: 'io.branch.sdk.android:library',
                  oldVersion: '5.21.2',
                  newVersion: '5.21.3',
                ),
              ],
            );
          });

          test('does not compare versions when DEX files match', () async {
            final fileSetDiff = await differ.changedFiles(
              withDependencies(
                baseAabPath,
                appDependencies([mavenLibrary('a', 'b', '1.0.0')]),
              ),
              withDependencies(
                changedDartAabPath,
                appDependencies([mavenLibrary('a', 'b', '2.0.0')]),
              ),
            );
            expect(
              fileSetDiff.dependencyVersionChanges,
              isEmpty,
            );
          });

          test('reports nothing when metadata is missing', () async {
            final fileSetDiff = await differ.changedFiles(
              withDependencies(baseAabPath, null),
              withDependencies(
                changedKotlinAabPath,
                appDependencies([mavenLibrary('a', 'b', '1.0.0')]),
              ),
            );
            expect(differ.nativeFileSetDiff(fileSetDiff), isNotEmpty);
            expect(
              fileSetDiff.dependencyVersionChanges,
              isEmpty,
            );
          });

          test('reports nothing when metadata is malformed', () async {
            final fileSetDiff = await differ.changedFiles(
              withDependencies(baseAabPath, Uint8List.fromList([0x80])),
              withDependencies(
                changedKotlinAabPath,
                appDependencies([mavenLibrary('a', 'b', '1.0.0')]),
              ),
            );
            expect(differ.nativeFileSetDiff(fileSetDiff), isNotEmpty);
            expect(
              fileSetDiff.dependencyVersionChanges,
              isEmpty,
            );
          });
        });

        test('detects dart changes', () async {
          final fileSetDiff = await differ.changedFiles(
            baseAabPath,
            changedDartAabPath,
          );
          expect(differ.assetsFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });

        test('detects dart and asset changes', () async {
          final fileSetDiff = await differ.changedFiles(
            baseAabPath,
            changedDartAndAssetAabPath,
          );
          expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });
      });
    });

    group('aar', () {
      group('changedFiles', () {
        test('finds no differences between the same aar', () async {
          expect(await differ.changedFiles(baseAarPath, baseAarPath), isEmpty);
        });

        test('finds differences between two different aars', () async {
          final fileSetDiff = await differ.changedFiles(
            baseAarPath,
            changedDartAarPath,
          );
          expect(fileSetDiff.changedPaths, {'jni/arm64-v8a/libapp.so'});
        });
      });

      group('changedFiles', () {
        test('detects no differences between the same aar', () async {
          expect(await differ.changedFiles(baseAarPath, baseAarPath), isEmpty);
        });

        test('detects asset changes', () async {
          final fileSetDiff = await differ.changedFiles(
            baseAarPath,
            changedAssetAarPath,
          );
          expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });

        test('detects dart changes', () async {
          final fileSetDiff = await differ.changedFiles(
            baseAarPath,
            changedDartAarPath,
          );
          expect(differ.assetsFileSetDiff(fileSetDiff), isEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });

        test('detects dart and asset changes', () async {
          final fileSetDiff = await differ.changedFiles(
            baseAarPath,
            changedDartAndAssetAarPath,
          );
          expect(differ.assetsFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.dartFileSetDiff(fileSetDiff), isNotEmpty);
          expect(differ.nativeFileSetDiff(fileSetDiff), isEmpty);
        });
      });

      group('containsPotentiallyBreakingAssetDiffs', () {
        test('returns true if assets were added', () {
          const fileSetDiff = FileSetDiff(
            addedPaths: {'base/assets/flutter_assets/file.json'},
            removedPaths: {},
            changedPaths: {},
          );
          expect(
            differ.containsPotentiallyBreakingAssetDiffs(fileSetDiff),
            isTrue,
          );
        });

        test('returns true if changed assets are not in the ignore list', () {
          const fileSetDiff = FileSetDiff(
            addedPaths: {},
            removedPaths: {},
            changedPaths: {
              'AssetManifest.bin',
              'AssetManifest.json',
              'base/assets/file.json',
            },
          );
          expect(
            differ.containsPotentiallyBreakingAssetDiffs(fileSetDiff),
            isTrue,
          );
        });

        test('returns false if changed assets are in the ignore list', () {
          const fileSetDiff = FileSetDiff(
            addedPaths: {},
            removedPaths: {},
            changedPaths: {
              'base/assets/flutter_assets/AssetManifest.bin',
              'base/assets/flutter_assets/AssetManifest.json',
              'base/assets/flutter_assets/NOTICES.Z',
            },
          );
          expect(
            differ.containsPotentiallyBreakingAssetDiffs(fileSetDiff),
            isFalse,
          );
        });
      });

      group('containsPotentiallyBreakingNativeDiffs', () {
        test('returns true if any native files have been added', () {
          const fileSetDiff = FileSetDiff(
            addedPaths: {'base/lib/arm64-v8a/test.dex'},
            removedPaths: {},
            changedPaths: {},
          );
          expect(
            differ.containsPotentiallyBreakingNativeDiffs(fileSetDiff),
            isTrue,
          );
        });

        test('returns true if any native files have been removed', () {
          const fileSetDiff = FileSetDiff(
            addedPaths: {},
            removedPaths: {'base/lib/arm64-v8a/test.dex'},
            changedPaths: {},
          );
          expect(
            differ.containsPotentiallyBreakingNativeDiffs(fileSetDiff),
            isTrue,
          );
        });

        test('returns true if any native files have been changed', () {
          const fileSetDiff = FileSetDiff(
            addedPaths: {},
            removedPaths: {},
            changedPaths: {'base/lib/arm64-v8a/test.dex'},
          );
          expect(
            differ.containsPotentiallyBreakingNativeDiffs(fileSetDiff),
            isTrue,
          );
        });

        test('returns false if no native files have been changed', () {
          final fileSetDiff = FileSetDiff.empty();
          expect(
            differ.containsPotentiallyBreakingNativeDiffs(fileSetDiff),
            isFalse,
          );
        });
      });
    });
  });
}

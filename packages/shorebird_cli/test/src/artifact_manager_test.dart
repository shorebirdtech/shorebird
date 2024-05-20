import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'mocks.dart';

void main() {
  group(ArtifactManager, () {
    late Cache cache;
    late Directory cacheArtifactDirectory;
    late http.Client httpClient;
    late Directory projectRoot;
    late PatchExecutable patchExecutable;
    late ShorebirdLogger logger;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess shorebirdProcess;
    late UpdaterTools updaterTools;
    late ArtifactManager artifactManager;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          cacheRef.overrideWith(() => cache),
          httpClientRef.overrideWith(() => httpClient),
          loggerRef.overrideWith(() => logger),
          patchExecutableRef.overrideWith(() => patchExecutable),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          updaterToolsRef.overrideWith(() => updaterTools),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(File(''));
      registerFallbackValue(FakeBaseRequest());
    });

    setUp(() {
      cacheArtifactDirectory = Directory.systemTemp.createTempSync();
      cache = MockCache();
      httpClient = MockHttpClient();
      logger = MockShorebirdLogger();
      patchExecutable = MockPatchExecutable();
      projectRoot = Directory.systemTemp.createTempSync();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();
      updaterTools = MockUpdaterTools();

      when(() => cache.getArtifactDirectory(any()))
          .thenReturn(cacheArtifactDirectory);
      when(() => cache.updateAll()).thenAnswer((_) async {});

      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
      );

      when(
        () => patchExecutable.run(
          releaseArtifactPath: any(
            named: 'releaseArtifactPath',
          ),
          patchArtifactPath: any(
            named: 'patchArtifactPath',
          ),
          diffPath: any(
            named: 'diffPath',
          ),
        ),
      ).thenAnswer(
        (_) async {},
      );

      when(() => shorebirdEnv.getShorebirdProjectRoot())
          .thenReturn(projectRoot);

      when(() => updaterTools.path).thenReturn('updater_tools');

      artifactManager = ArtifactManager();
    });

    group('createDiff', () {
      late File releaseArtifactFile;
      late File patchArtifactFile;

      setUp(() {
        final tmpDir = Directory.systemTemp.createTempSync();
        releaseArtifactFile = File(p.join(tmpDir.path, 'release_artifact'))
          ..createSync(recursive: true);
        patchArtifactFile = File(p.join(tmpDir.path, 'patch_artifact'))
          ..createSync(recursive: true);

        when(
          () => updaterTools.createDiff(
            releaseArtifact: any(named: 'releaseArtifact'),
            patchArtifact: any(named: 'patchArtifact'),
            outputFile: any(named: 'outputFile'),
          ),
        ).thenAnswer((_) async => {});
      });

      test('throws error when release artifact file does not exist', () async {
        await expectLater(
          () => runWithOverrides(
            () async => artifactManager.createDiff(
              releaseArtifact: File('not/a/real/file'),
              patchArtifact: patchArtifactFile,
            ),
          ),
          throwsA(
            isA<FileSystemException>()
                .having(
                  (e) => e.message,
                  'message',
                  'Release artifact does not exist',
                )
                .having(
                  (e) => e.path,
                  'path',
                  'not/a/real/file',
                ),
          ),
        );
      });

      test('throws error when patch artfiact file does not exist', () async {
        await expectLater(
          () => runWithOverrides(
            () async => artifactManager.createDiff(
              releaseArtifact: releaseArtifactFile,
              patchArtifact: File('not/a/real/file'),
            ),
          ),
          throwsA(
            isA<FileSystemException>()
                .having(
                  (e) => e.message,
                  'message',
                  'Patch artifact does not exist',
                )
                .having(
                  (e) => e.path,
                  'path',
                  'not/a/real/file',
                ),
          ),
        );
      });

      test('throws error when creating diff fails', () async {
        when(
          () => patchExecutable.run(
            releaseArtifactPath: releaseArtifactFile.path,
            patchArtifactPath: patchArtifactFile.path,
            diffPath: any(named: 'diffPath'),
          ),
        ).thenThrow(
          PatchFailedException('error'),
        );

        await expectLater(
          () => runWithOverrides(
            () async => artifactManager.createDiff(
              releaseArtifact: releaseArtifactFile,
              patchArtifact: patchArtifactFile,
            ),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception',
              'error',
            ),
          ),
        );
      });

      test('returns diff path when creating diff succeeds', () async {
        final diffPath = await runWithOverrides(
          () => artifactManager.createDiff(
            releaseArtifact: releaseArtifactFile,
            patchArtifact: patchArtifactFile,
          ),
        );

        expect(diffPath, endsWith('diff.patch'));
        verify(
          () => patchExecutable.run(
            releaseArtifactPath: releaseArtifactFile.path,
            patchArtifactPath: patchArtifactFile.path,
            diffPath: any(named: 'diffPath', that: endsWith('diff.patch')),
          ),
        ).called(1);
      });

      group('when updater-tools is present', () {
        setUp(() {
          final tempDir = Directory.systemTemp.createTempSync();
          final updaterToolsFile = File(p.join(tempDir.path, 'updater_tools'))
            ..createSync();
          when(() => updaterTools.path).thenReturn(updaterToolsFile.path);
        });

        test('uses updater-tools instead of patch to create diff', () async {
          await runWithOverrides(
            () => artifactManager.createDiff(
              releaseArtifact: releaseArtifactFile,
              patchArtifact: patchArtifactFile,
            ),
          );

          verify(
            () => updaterTools.createDiff(
              releaseArtifact: releaseArtifactFile,
              patchArtifact: patchArtifactFile,
              outputFile: any(named: 'outputFile'),
            ),
          ).called(1);

          verifyNever(
            () => patchExecutable.run(
              releaseArtifactPath: any(named: 'releaseArtifactPath'),
              patchArtifactPath: any(named: 'patchArtifactPath'),
              diffPath: any(named: 'diffPath'),
            ),
          );
        });
      });
    });

    group('downloadFile', () {
      test('throws exception when file download fails', () async {
        const error = 'Not Found';
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.notFound,
            reasonPhrase: error,
          ),
        );

        await expectLater(
          () => runWithOverrides(
            () async => artifactManager.downloadFile(
              Uri.parse('https://example.com'),
            ),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception',
              'Exception: Failed to download file: 404 $error',
            ),
          ),
        );
      });

      test('returns path to file when download succeeds', () async {
        final result = await runWithOverrides(
          () async => artifactManager.downloadFile(
            Uri.parse('https://example.com'),
          ),
        );

        expect(result.path, endsWith('artifact'));
      });

      test('returns provided output path when specified', () async {
        final tempDir = Directory.systemTemp.createTempSync();
        final outFile = File(p.join(tempDir.path, 'file.out'));
        final result = await runWithOverrides(
          () async => artifactManager.downloadFile(
            Uri.parse('https://example.com'),
            outputPath: outFile.path,
          ),
        );

        expect(result.path, equals(outFile.path));
      });
    });

    group('extractZip', () {
      test('unzips provided file to provided output path', () async {
        final zipFile = File(p.join('test', 'fixtures', 'aabs', 'base.aab'));
        final tempDir = Directory.systemTemp.createTempSync();

        expect(tempDir.listSync(recursive: true), isEmpty);
        await expectLater(
          runWithOverrides(
            () => artifactManager.extractZip(
              zipFile: zipFile,
              outputDirectory: tempDir,
            ),
          ),
          completes,
        );
        expect(tempDir.listSync(recursive: true), hasLength(146));
      });
    });

    group('androidArchsDirectory', () {
      late Directory projectRoot;
      late Directory strippedNativeLibsDirectory;

      setUp(() {
        projectRoot = Directory.systemTemp.createTempSync();
        strippedNativeLibsDirectory = Directory(
          p.join(
            projectRoot.path,
            'build',
            'app',
            'intermediates',
            'stripped_native_libs',
          ),
        )..createSync(recursive: true);
      });

      group('without flavor', () {
        setUp(() {});

        test('returns null if no directories exist at the expected paths', () {
          final result = ArtifactManager.androidArchsDirectory(
            projectRoot: projectRoot,
          );

          expect(result, isNull);
        });

        test('returns a path containing stripReleaseDebugSymbols if it exists',
            () {
          final stripNativeDebugLibsDirectory = Directory(
            p.join(
              strippedNativeLibsDirectory.path,
              'release',
              'stripReleaseDebugSymbols',
              'out',
              'lib',
            ),
          )..createSync(recursive: true);

          // Create paths with and without the stripReleaseDebugSymbols
          // directory to ensure the method returns the correct path when both
          // exist.
          Directory(
            p.join(
              strippedNativeLibsDirectory.path,
              'release',
              'out',
              'lib',
            ),
          ).createSync(recursive: true);

          final result = ArtifactManager.androidArchsDirectory(
            projectRoot: projectRoot,
          );

          expect(result, isNotNull);
          expect(result!.path, equals(stripNativeDebugLibsDirectory.path));
        });

        test(
            '''returns a path not containing stripReleaseDebugSymbols no path containing stripReleaseDebugSymbols exists''',
            () {
          final noStripReleaseDebugSymbolsPath = Directory(
            p.join(
              strippedNativeLibsDirectory.path,
              'release',
              'out',
              'lib',
            ),
          )..createSync(recursive: true);

          final result = ArtifactManager.androidArchsDirectory(
            projectRoot: projectRoot,
          );

          expect(result, isNotNull);
          expect(result!.path, equals(noStripReleaseDebugSymbolsPath.path));
        });
      });

      group('with a flavor named "internal"', () {
        const flavor = 'internal';

        test('returns null if no directories exist at the expected paths', () {
          final result = ArtifactManager.androidArchsDirectory(
            projectRoot: projectRoot,
            flavor: flavor,
          );

          expect(result, isNull);
        });

        test(
            '''returns a path containing stripInternalReleaseDebugSymbols if it exists''',
            () {
          final stripNativeDebugLibsDirectory = Directory(
            p.join(
              strippedNativeLibsDirectory.path,
              'internalRelease',
              'stripInternalReleaseDebugSymbols',
              'out',
              'lib',
            ),
          )..createSync(recursive: true);

          // Create paths with and without the stripReleaseDebugSymbols
          // directory to ensure the method returns the correct path when both
          // exist.
          Directory(
            p.join(
              strippedNativeLibsDirectory.path,
              'internalRelease',
              'out',
              'lib',
            ),
          ).createSync(recursive: true);

          final result = ArtifactManager.androidArchsDirectory(
            projectRoot: projectRoot,
            flavor: flavor,
          );

          expect(result, isNotNull);
          expect(result!.path, equals(stripNativeDebugLibsDirectory.path));
        });

        test(
            '''returns a path not containing stripInternalReleaseDebugSymbols no path containing stripInternalReleaseDebugSymbols exists''',
            () {
          final noStripReleaseDebugSymbolsPath = Directory(
            p.join(
              strippedNativeLibsDirectory.path,
              'internalRelease',
              'out',
              'lib',
            ),
          )..createSync(recursive: true);

          final result = ArtifactManager.androidArchsDirectory(
            projectRoot: projectRoot,
            flavor: flavor,
          );

          expect(result, isNotNull);
          expect(result!.path, equals(noStripReleaseDebugSymbolsPath.path));
        });
      });
    });

    group('getXcarchiveDirectory', () {
      group('when archive directory exists', () {
        late Directory archiveDirectory;

        setUp(() {
          archiveDirectory = Directory(
            p.join(
              projectRoot.path,
              'build',
              'ios',
              'archive',
              'Runner.xcarchive',
            ),
          )..createSync(recursive: true);
        });

        test('returns path to archive directory', () async {
          final result = runWithOverrides(
            () => artifactManager.getXcarchiveDirectory(),
          );

          expect(result, isNotNull);
          expect(result!.path, equals(archiveDirectory.path));
        });
      });

      group('when archive directory does not exist', () {
        test('returns null', () {
          expect(
            runWithOverrides(artifactManager.getXcarchiveDirectory),
            isNull,
          );
        });
      });
    });

    group('getIosAppDirectory', () {
      group('when applications directory does not exist', () {
        test('returns null', () {
          final xcarchiveDirectory = Directory.systemTemp.createTempSync();
          expect(
            runWithOverrides(
              () => artifactManager.getIosAppDirectory(
                xcarchiveDirectory: xcarchiveDirectory,
              ),
            ),
            isNull,
          );
        });
      });

      group('when applications directory exists', () {
        late Directory applicationsDirectory;
        late Directory xcarchiveDirectory;

        setUp(() {
          xcarchiveDirectory = Directory.systemTemp.createTempSync();
          applicationsDirectory = Directory(
            p.join(
              xcarchiveDirectory.path,
              'Products',
              'Applications',
              'Runner.app',
            ),
          )..createSync(recursive: true);
        });

        test('returns path to applications directory', () {
          final result = runWithOverrides(
            () => artifactManager.getIosAppDirectory(
              xcarchiveDirectory: xcarchiveDirectory,
            ),
          );

          expect(result, isNotNull);
          expect(result!.path, equals(applicationsDirectory.path));
        });
      });
    });

    group('getIpa', () {
      group('when ipa build directory does not exist', () {
        test('returns null', () {
          expect(
            runWithOverrides(artifactManager.getIpa),
            isNull,
          );
        });
      });

      group('when ipa build directory exists', () {
        late Directory ipaBuildDirectory;
        late File ipaFile;

        setUp(() {
          ipaBuildDirectory = Directory(
            p.join(
              projectRoot.path,
              'build',
              'ios',
              'ipa',
            ),
          )..createSync(recursive: true);
          ipaFile = File(p.join(ipaBuildDirectory.path, 'Runner.ipa'))
            ..createSync();
        });

        test('returns path to ipa file', () {
          final result = runWithOverrides(artifactManager.getIpa);

          expect(result, isNotNull);
          expect(result!.path, equals(ipaFile.path));
        });

        test('returns null when multiple ipa files exist', () {
          File(p.join(ipaBuildDirectory.path, 'Runner2.ipa')).createSync();

          expect(
            runWithOverrides(artifactManager.getIpa),
            isNull,
          );
          verify(
            () => logger.detail(
              'More than one .ipa file found in ${ipaBuildDirectory.path}',
            ),
          );
        });

        test('returns null when no ipa files exist', () {
          ipaFile.deleteSync();

          expect(
            runWithOverrides(artifactManager.getIpa),
            isNull,
          );

          verify(
            () => logger.detail(
              'No .ipa files found in ${ipaBuildDirectory.path}',
            ),
          );
        });
      });
    });

    group('getAppXcframeworkPath', () {
      test('returns path to App.xcframework', () {
        expect(
          runWithOverrides(artifactManager.getAppXcframeworkPath),
          equals(
            p.join(
              projectRoot.path,
              'build',
              'ios',
              'framework',
              'Release',
              ArtifactManager.appXcframeworkName,
            ),
          ),
        );
      });
    });

    group('getAppXcframeworkDirectory', () {
      test('returns directory containing App.xcframework', () {
        expect(
          runWithOverrides(artifactManager.getAppXcframeworkDirectory).path,
          equals(
            p.join(
              projectRoot.path,
              'build',
              'ios',
              'framework',
              'Release',
            ),
          ),
        );
      });
    });

    group('newestAppDill', () {
      late File appDill2;

      setUp(() {
        final tempDir = Directory.systemTemp.createTempSync();
        when(() => shorebirdEnv.getShorebirdProjectRoot()).thenReturn(tempDir);
        final flutterBuildDir = Directory(
          p.join(tempDir.path, '.dart_tool', 'flutter_build'),
        )..createSync(recursive: true);
        File(p.join(flutterBuildDir.path, 'app1', 'app.dill'))
          ..createSync(recursive: true)
          ..setLastModifiedSync(
            DateTime.now().subtract(const Duration(days: 1)),
          );
        appDill2 = File(p.join(flutterBuildDir.path, 'app2', 'app.dill'))
          ..createSync(recursive: true);
      });

      test('selects the most recently edited .app.dill file', () {
        final result = runWithOverrides(artifactManager.newestAppDill);

        expect(result, isNotNull);
        expect(result.path, equals(appDill2.path));
      });
    });
  });
}

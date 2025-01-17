import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'mocks.dart';

void main() {
  group(ArtifactManager, () {
    late ArtifactManager artifactManager;
    late Cache cache;
    late Directory cacheArtifactDirectory;
    late http.Client httpClient;
    late Directory projectRoot;
    late PatchExecutable patchExecutable;
    late ShorebirdLogger logger;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess shorebirdProcess;

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
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(FakeBaseRequest());
    });

    setUp(() {
      cacheArtifactDirectory = Directory.systemTemp.createTempSync();
      cache = MockCache();
      httpClient = MockHttpClient();
      logger = MockShorebirdLogger();
      projectRoot = Directory.systemTemp.createTempSync();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();

      when(() => cache.getArtifactDirectory(any()))
          .thenReturn(cacheArtifactDirectory);
      when(() => cache.updateAll()).thenAnswer((_) async {});

      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
      );

      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);

      artifactManager = ArtifactManager();

      patchExecutable = MockPatchExecutable();
      when(
        () => patchExecutable.run(
          releaseArtifactPath: any(named: 'releaseArtifactPath'),
          patchArtifactPath: any(named: 'patchArtifactPath'),
          diffPath: any(named: 'diffPath'),
        ),
      ).thenAnswer((_) async {});
    });

    group('createDiff', () {
      late File releaseArtifactFile;
      late File patchArtifactFile;

      setUp(() {
        final tmpDir = Directory.systemTemp.createTempSync();
        releaseArtifactFile = File(
          p.join(tmpDir.path, 'release_artifact'),
        )..createSync(recursive: true);
        patchArtifactFile = File(
          p.join(tmpDir.path, 'patch_artifact'),
        )..createSync(recursive: true);
      });

      test('throws error when release artifact file does not exist', () async {
        await expectLater(
          () => runWithOverrides(
            () async => artifactManager.createDiff(
              releaseArtifactPath: 'not/a/real/file',
              patchArtifactPath: patchArtifactFile.path,
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

      test('throws error when patch artifact file does not exist', () async {
        await expectLater(
          () => runWithOverrides(
            () async => artifactManager.createDiff(
              releaseArtifactPath: releaseArtifactFile.path,
              patchArtifactPath: 'not/a/real/file',
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
              releaseArtifactPath: releaseArtifactFile.path,
              patchArtifactPath: patchArtifactFile.path,
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
            releaseArtifactPath: releaseArtifactFile.path,
            patchArtifactPath: patchArtifactFile.path,
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
    });

    group('downloadFileWithProgress', () {
      group('with progress update', () {
        group('when response contentLength is null', () {
          setUp(() {
            when(() => httpClient.send(any())).thenAnswer(
              (_) async => http.StreamedResponse(
                Stream.fromIterable([
                  [1],
                  [2],
                  [3],
                ]),
                HttpStatus.ok,
              ),
            );
          });

          test('does not add to stream', () async {
            final download = await runWithOverrides(
              () => artifactManager.startFileDownload(
                Uri.parse('https://example.com'),
              ),
            );

            expect(await download.progress.toList(), isEmpty);
          });
        });

        group('when response contentLength is not null', () {
          setUp(() {
            when(() => httpClient.send(any())).thenAnswer(
              (_) async => http.StreamedResponse(
                Stream.fromIterable([
                  [1],
                  [2],
                  [3],
                ]),
                HttpStatus.ok,
                contentLength: 3,
              ),
            );
          });

          test('calls onProgress with correct percentage', () async {
            final download = await runWithOverrides(
              () => artifactManager.startFileDownload(
                Uri.parse('https://example.com'),
              ),
            );

            expect(download.progress, emitsInOrder([1 / 3, 2 / 3, 3 / 3]));
          });

          test('uses outputPath when specified', () async {
            final tempDir = Directory.systemTemp.createTempSync();
            final outputPath = p.join(tempDir.path, 'output-file.txt');
            final download = await runWithOverrides(
              () => artifactManager.startFileDownload(
                Uri.parse('https://example.com'),
                outputPath: outputPath,
              ),
            );
            final file = await download.file;
            expect(file.path, equals(outputPath));
            expect(file.lengthSync(), equals(3));
          });
        });
      });
    });

    group('downloadWithProgressUpdates', () {
      late Progress progress;

      setUp(() {
        progress = MockProgress();
        when(() => logger.progress(any())).thenReturn(progress);
      });

      group('when download fails', () {
        setUp(() {
          const error = 'Not Found';
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.notFound,
              reasonPhrase: error,
            ),
          );
        });

        test('progress fails with error message', () async {
          await expectLater(
            runWithOverrides(
              () => artifactManager.downloadWithProgressUpdates(
                Uri.parse('https://example.com'),
                message: 'hello',
              ),
            ),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'exception',
                'Exception: Failed to download file: 404 Not Found',
              ),
            ),
          );

          verify(
            () => progress.fail(
              '''hello failed: Exception: Failed to download file: 404 Not Found''',
            ),
          ).called(1);
        });
      });

      group(
        'when download succeeds',
        () {
          late StreamController<List<int>> responseStreamController;

          setUp(() {
            responseStreamController = StreamController<List<int>>();
            when(() => httpClient.send(any())).thenAnswer(
              (_) async => http.StreamedResponse(
                responseStreamController.stream,
                HttpStatus.ok,
                contentLength: 5,
              ),
            );
          });

          test('progress updates with a throttled ', () async {
            // Awaiting this will cause the test to hang
            unawaited(
              runWithOverrides(
                () => artifactManager.downloadWithProgressUpdates(
                  Uri.parse('https://example.com'),
                  message: 'hello',
                  throttleDuration: const Duration(milliseconds: 50),
                ),
              ),
            );
            // Download the first 3/5. The first addition will trigger the first
            // progress update, the second addition will be throttled, and the
            // third addition will trigger the second progress update after the
            // delay.
            responseStreamController
              ..add([1])
              ..add([1])
              ..add([1]);
            await Future<void>.delayed(const Duration(milliseconds: 70));
            // Download the last 2/5, bringing the total to 5/5
            responseStreamController.add([1, 1]);
            await Future<void>.delayed(const Duration(milliseconds: 70));
            verifyInOrder([
              () => progress.update('hello (20%)'),
              () => progress.update('hello (60%)'),
              () => progress.update('hello (100%)'),
            ]);
            verifyNever(() => progress.update('hello (0%)'));
            verifyNever(() => progress.update('hello (20%)'));
            verifyNever(() => progress.update('hello (80%)'));
            verifyNoMoreInteractions(progress);
            await responseStreamController.close();
          });
        },
        onPlatform: {
          'windows': const Skip('Flaky on Windows'),
        },
      );
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

      group(
        'when multiple xcarchive directories exist',
        () {
          late Directory oldArchiveDirectory;
          late Directory newArchiveDirectory;

          setUp(() async {
            oldArchiveDirectory = Directory(
              p.join(
                projectRoot.path,
                'build',
                'ios',
                'archive',
                'Runner.xcarchive',
              ),
            )..createSync(recursive: true);
            // Wait to ensure the new archive directory is created after the old
            // archive directory.
            await Future<void>.delayed(const Duration(milliseconds: 50));
            newArchiveDirectory = Directory(
              p.join(
                projectRoot.path,
                'build',
                'ios',
                'archive',
                'Runner2.xcarchive',
              ),
            )..createSync(recursive: true);
          });

          test('selects the most recently updated xcarchive', () async {
            final firstResult = runWithOverrides(
              () => artifactManager.getXcarchiveDirectory(),
            );
            // The new archive directory should be selected because it was
            // created after the old archive directory.
            expect(firstResult!.path, equals(newArchiveDirectory.path));

            // Now recreate the old archive directory and ensure it is selected.
            oldArchiveDirectory.deleteSync(recursive: true);
            oldArchiveDirectory = Directory(
              p.join(
                projectRoot.path,
                'build',
                'ios',
                'archive',
                'Runner.xcarchive',
              ),
            )..createSync(recursive: true);
            final secondResult = runWithOverrides(
              () => artifactManager.getXcarchiveDirectory(),
            );
            expect(secondResult!.path, equals(oldArchiveDirectory.path));
          });
        },
        onPlatform: {
          'windows': const Skip('Flaky on Windows'),
        },
      );

      group('when archive directory does not exist', () {
        test('returns null', () {
          expect(
            runWithOverrides(artifactManager.getXcarchiveDirectory),
            isNull,
          );
        });
      });
    });

    group('getMacOSAppDirectory', () {
      group('when .app directory exists', () {
        late Directory archiveDirectory;

        setUp(() {
          archiveDirectory = Directory(
            p.join(
              projectRoot.path,
              'build',
              'macos',
              'Build',
              'Products',
              'Release',
              'Runner.app',
            ),
          )..createSync(recursive: true);
        });

        test('returns path to app directory', () async {
          final result = runWithOverrides(
            () => artifactManager.getMacOSAppDirectory(),
          );

          expect(result!.path, equals(archiveDirectory.path));
        });
      });

      group(
        'when multiple .app directories exist',
        () {
          late Directory oldAppDirectory;
          late Directory newAppDirectory;

          setUp(() async {
            oldAppDirectory = Directory(
              p.join(
                projectRoot.path,
                'build',
                'macos',
                'Build',
                'Products',
                'Release',
                'Runner.app',
              ),
            )..createSync(recursive: true);
            // Wait to ensure the new app directory is created after the old
            // app directory.
            await Future<void>.delayed(const Duration(milliseconds: 50));
            newAppDirectory = Directory(
              p.join(
                projectRoot.path,
                'build',
                'macos',
                'Build',
                'Products',
                'Release',
                'Runner2.app',
              ),
            )..createSync(recursive: true);
          });

          test('selects the most recently updated app', () async {
            final firstResult = runWithOverrides(
              artifactManager.getMacOSAppDirectory,
            );
            // The new app directory should be selected because it was
            // created after the old app directory.
            expect(firstResult!.path, equals(newAppDirectory.path));

            // Now recreate the old app directory and ensure it is selected.
            oldAppDirectory.deleteSync(recursive: true);
            oldAppDirectory = Directory(
              p.join(
                projectRoot.path,
                'build',
                'macos',
                'Build',
                'Products',
                'Release',
                'Runner.app',
              ),
            )..createSync(recursive: true);
            final secondResult = runWithOverrides(
              artifactManager.getMacOSAppDirectory,
            );
            expect(secondResult!.path, equals(oldAppDirectory.path));
          });
        },
        testOn: 'mac-os',
      );

      group('when app directory does not exist', () {
        test('returns null', () {
          expect(
            runWithOverrides(artifactManager.getMacOSAppDirectory),
            isNull,
          );
        });
      });

      group('when a flavor is provided', () {
        const flavor = 'my-flavor';
        late Directory appDirectory;

        setUp(() {
          appDirectory = Directory(
            p.join(
              projectRoot.path,
              'build',
              'macos',
              'Build',
              'Products',
              'Release-$flavor',
              'my.app',
            ),
          )..createSync(recursive: true);
        });

        test('includes flavor in lookup path', () async {
          final result = runWithOverrides(
            () => artifactManager.getMacOSAppDirectory(flavor: flavor),
          );

          expect(result!.path, equals(appDirectory.path));
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

    group('getWindowsReleaseDirectory', () {
      test('returns correct path', () {
        expect(
          runWithOverrides(artifactManager.getWindowsReleaseDirectory).path,
          equals(
            p.join(
              projectRoot.path,
              'build',
              'windows',
              'x64',
              'runner',
              'Release',
            ),
          ),
        );
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

    group('getIosReleaseSupplementDirectory', () {
      group('when the directory does not exist', () {
        test('returns null', () {
          expect(
            runWithOverrides(artifactManager.getIosReleaseSupplementDirectory),
            isNull,
          );
        });
      });

      group('when the directory exists', () {
        setUp(() {
          Directory(
            p.join(
              projectRoot.path,
              'build',
              'ios',
              'shorebird',
            ),
          ).createSync(recursive: true);
        });

        test('returns path to the directory', () {
          expect(
            runWithOverrides(
              artifactManager.getIosReleaseSupplementDirectory,
            )?.path,
            equals(
              p.join(
                projectRoot.path,
                'build',
                'ios',
                'shorebird',
              ),
            ),
          );
        });
      });
    });

    group('getMacosReleaseSupplementDirectory', () {
      group('when the directory does not exist', () {
        test('returns null', () {
          expect(
            runWithOverrides(
              artifactManager.getMacosReleaseSupplementDirectory,
            ),
            isNull,
          );
        });
      });

      group('when the directory exists', () {
        setUp(() {
          Directory(
            p.join(
              projectRoot.path,
              'build',
              'macos',
              'shorebird',
            ),
          ).createSync(recursive: true);
        });

        test('returns path to the directory', () {
          expect(
            runWithOverrides(
              artifactManager.getMacosReleaseSupplementDirectory,
            )?.path,
            equals(
              p.join(
                projectRoot.path,
                'build',
                'macos',
                'shorebird',
              ),
            ),
          );
        });
      });
    });
  });
}

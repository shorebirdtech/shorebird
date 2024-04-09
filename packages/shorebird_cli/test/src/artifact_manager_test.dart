import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'mocks.dart';

void main() {
  group(ArtifactManager, () {
    late Cache cache;
    late Directory cacheArtifactDirectory;
    late http.Client httpClient;
    late ShorebirdProcessResult patchProcessResult;
    late ShorebirdProcess shorebirdProcess;
    late ArtifactManager artifactManager;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          cacheRef.overrideWith(() => cache),
          httpClientRef.overrideWith(() => httpClient),
          processRef.overrideWith(() => shorebirdProcess),
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
      patchProcessResult = MockProcessResult();
      shorebirdProcess = MockShorebirdProcess();
      artifactManager = ArtifactManager();

      when(() => cache.getArtifactDirectory(any()))
          .thenReturn(cacheArtifactDirectory);
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
      );
      when(
        () => shorebirdProcess.run(
          any(that: endsWith('patch')),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.positionalArguments[1] as List<String>;
        final diffPath = args[2];
        File(diffPath)
          ..createSync(recursive: true)
          ..writeAsStringSync('diff');
        return patchProcessResult;
      });
      when(() => patchProcessResult.exitCode).thenReturn(ExitCode.success.code);
    });

    group('createDiff', () {
      const releaseArtifactPath = 'path/to/release_artifact';
      const patchArtifactPath = 'path/to/patch_artifact';

      test('throws error when creating diff fails', () async {
        const stdout = 'uh oh';
        const stderr = 'oops something went wrong';
        when(() => patchProcessResult.exitCode).thenReturn(1);
        when(() => patchProcessResult.stderr).thenReturn(stderr);
        when(() => patchProcessResult.stdout).thenReturn(stdout);

        await expectLater(
          () => runWithOverrides(
            () async => artifactManager.createDiff(
              releaseArtifactPath: releaseArtifactPath,
              patchArtifactPath: patchArtifactPath,
            ),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'exception',
              'Exception: Failed to create diff (exit code 1).\n'
                  '  stdout: $stdout\n'
                  '  stderr: $stderr',
            ),
          ),
        );
      });

      test('returns diff path when creating diff succeeds', () async {
        final diffPath = await runWithOverrides(
          () => artifactManager.createDiff(
            releaseArtifactPath: releaseArtifactPath,
            patchArtifactPath: patchArtifactPath,
          ),
        );

        expect(diffPath, endsWith('diff.patch'));
        verify(
          () => shorebirdProcess.run(
            p.join(cacheArtifactDirectory.path, 'patch'),
            any(
              that: containsAllInOrder([
                releaseArtifactPath,
                patchArtifactPath,
                endsWith('diff.patch'),
              ]),
            ),
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

      test(
        'unzips large file to provided output path',
        () async {
          // Prevent regressions where extractZip closes the input sync too soon.
          // https://github.com/shorebirdtech/shorebird/pull/1866
          final tempDir = Directory.systemTemp.createTempSync();
          final outDir = Directory.systemTemp.createTempSync();
          final file = File(p.join(tempDir.path, 'large.txt'))
            ..writeAsBytesSync(
              List.generate(999999999, (index) => index),
            );
          final zipFile = File(p.join(tempDir.path, 'large.zip'));
          final encoder = ZipFileEncoder()..open(zipFile.path);
          await encoder.addFile(file);
          encoder.close();

          expect(outDir.listSync(recursive: true), isEmpty);
          await expectLater(
            runWithOverrides(
              () => artifactManager.extractZip(
                zipFile: zipFile,
                outputDirectory: outDir,
              ),
            ),
            completes,
          );
          expect(outDir.listSync(recursive: true), hasLength(1));
          expect(
              File(p.join(outDir.path, 'large.txt')).lengthSync(), 999999999);
        },
        timeout: const Timeout.factor(2),
      );
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
  });
}

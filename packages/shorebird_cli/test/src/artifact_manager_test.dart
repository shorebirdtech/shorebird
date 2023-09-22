import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'mocks.dart';

void main() {
  group(ArtifactManager, () {
    late Cache cache;
    late Directory cacheArtifactDirectory;
    late ShorebirdProcessResult patchProcessResult;
    late ShorebirdProcess shorebirdProcess;
    late ArtifactManager artifactManager;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          cacheRef.overrideWith(() => cache),
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
      patchProcessResult = MockProcessResult();
      shorebirdProcess = MockShorebirdProcess();
      artifactManager = ArtifactManager();

      when(() => cache.getArtifactDirectory(any()))
          .thenReturn(cacheArtifactDirectory);
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
        const error = 'oops something went wrong';
        when(() => patchProcessResult.exitCode).thenReturn(1);
        when(() => patchProcessResult.stderr).thenReturn(error);

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
              'Exception: Failed to create diff: $error',
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
      late http.Client httpClient;

      setUp(() {
        httpClient = MockHttpClient();

        when(() => httpClient.send(any())).thenAnswer(
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
        );
      });

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
              httpClient: httpClient,
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
        final result = runWithOverrides(
          () async => artifactManager.downloadFile(
            Uri.parse('https://example.com'),
            httpClient: httpClient,
          ),
        );

        await expectLater(
          result,
          completion(endsWith('artifact')),
        );
      });

      test('returns provided output path when specified', () async {
        final tempDir = Directory.systemTemp.createTempSync();
        final outFile = File(p.join(tempDir.path, 'file.out'));
        final result = runWithOverrides(
          () async => artifactManager.downloadFile(
            Uri.parse('https://example.com'),
            httpClient: httpClient,
            outputPath: outFile.path,
          ),
        );

        await expectLater(result, completion(outFile.path));
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
              outputPath: tempDir.path,
            ),
          ),
          completes,
        );
        expect(tempDir.listSync(recursive: true), hasLength(146));
      });
    });
  });
}

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/checksum_checker.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'mocks.dart';

void main() {
  group(Cache, () {
    const shorebirdEngineRevision = 'test-revision';

    late ArtifactManager artifactManager;
    late Cache cache;
    late ChecksumChecker checksumChecker;
    late Directory shorebirdRoot;
    late http.Client httpClient;
    late ShorebirdLogger logger;
    late Platform platform;
    late Process chmodProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess shorebirdProcess;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          artifactManagerRef.overrideWith(() => artifactManager),
          cacheRef.overrideWith(() => cache),
          checksumCheckerRef.overrideWith(() => checksumChecker),
          httpClientRef.overrideWith(() => httpClient),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    void setMockPlatform(String name) {
      assert(
        Platform.operatingSystemValues.contains(name),
        'Unrecognized platform name',
      );
      when(() => platform.isMacOS).thenReturn(name == 'macos');
      when(() => platform.isWindows).thenReturn(name == 'windows');
      when(() => platform.isLinux).thenReturn(name == 'linux');
      when(() => platform.isAndroid).thenReturn(name == 'android');
      when(() => platform.isFuchsia).thenReturn(name == 'fuchsia');
      when(() => platform.isIOS).thenReturn(name == 'ios');
    }

    setUpAll(() {
      registerFallbackValue(ChecksumAlgorithm.sha256);
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(FakeBaseRequest());
    });

    setUp(() {
      artifactManager = MockArtifactManager();
      chmodProcess = MockProcess();
      checksumChecker = MockChecksumChecker();
      httpClient = MockHttpClient();
      logger = MockShorebirdLogger();
      platform = MockPlatform();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdProcess = MockShorebirdProcess();

      shorebirdRoot = Directory.systemTemp.createTempSync();
      when(
        () => artifactManager.extractZip(
          zipFile: any(named: 'zipFile'),
          outputDirectory: any(named: 'outputDirectory'),
        ),
      ).thenAnswer((invocation) async {
        (invocation.namedArguments[#outputDirectory] as Directory)
            .createSync(recursive: true);
      });
      when(
        () => shorebirdEnv.shorebirdEngineRevision,
      ).thenReturn(shorebirdEngineRevision);
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);

      when(() => platform.environment).thenReturn({});
      setMockPlatform(Platform.macOS);
      when(() => shorebirdProcess.start(any(), any())).thenAnswer(
        (_) async => chmodProcess,
      );
      when(() => chmodProcess.exitCode).thenAnswer(
        (_) async => ExitCode.success.code,
      );
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(ZipEncoder().encode(Archive())!),
          HttpStatus.ok,
        ),
      );
      when(
        () => checksumChecker.checkFile(
          any(),
          checksum: any(named: 'checksum'),
          algorithm: any(named: 'algorithm'),
        ),
      ).thenReturn(true);

      cache = runWithOverrides(Cache.new);
    });

    test('can be instantiated w/out args', () {
      expect(Cache.new, returnsNormally);
    });

    group(CacheUpdateFailure, () {
      test('overrides toString', () {
        const exception = CacheUpdateFailure('test');
        expect(exception.toString(), equals('CacheUpdateFailure: test'));
      });
    });

    group('getArtifactDirectory', () {
      test('returns correct directory', () {
        final directory = runWithOverrides(
          () => cache.getArtifactDirectory('test'),
        );
        expect(
          directory.path.endsWith(
            p.join(
              'bin',
              'cache',
              'artifacts',
              'test',
            ),
          ),
          isTrue,
        );
      });
    });

    group('getPreviewDirectory', () {
      test('returns correct directory', () {
        final directory = runWithOverrides(
          () => cache.getPreviewDirectory('test'),
        );
        expect(
          directory.path.endsWith(
            p.join(
              'bin',
              'cache',
              'previews',
              'test',
            ),
          ),
          isTrue,
        );
      });
    });

    group('clear', () {
      test('deletes the cache directory', () async {
        final shorebirdCacheDirectory = runWithOverrides(
          () => Cache.shorebirdCacheDirectory,
        )..createSync(recursive: true);
        expect(shorebirdCacheDirectory.existsSync(), isTrue);
        await runWithOverrides(cache.clear);
        expect(shorebirdCacheDirectory.existsSync(), isFalse);
      });

      test('does nothing if directory does not exist', () {
        final shorebirdCacheDirectory = runWithOverrides(
          () => Cache.shorebirdCacheDirectory,
        );
        expect(shorebirdCacheDirectory.existsSync(), isFalse);
        runWithOverrides(cache.clear);
        expect(shorebirdCacheDirectory.existsSync(), isFalse);
      });
    });

    group('updateAll', () {
      group('when a crc32c checksum is provided', () {
        const crc32cChecksum = 'checksum';
        const md5Checksum = 'md5-checksum';
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(ZipEncoder().encode(Archive())!),
              HttpStatus.ok,
              headers: {
                'x-goog-hash': 'crc32c=$crc32cChecksum,md5=$md5Checksum',
              },
            ),
          );
        });

        test('verifies checksum', () async {
          await runWithOverrides(cache.updateAll);

          verify(
            () => checksumChecker.checkFile(
              any(),
              checksum: crc32cChecksum,
              algorithm: ChecksumAlgorithm.crc32c,
            ),
          ).called(2); // once per required artifact
        });
      });

      group('when an exception happens', () {
        const exception = SocketException('test');

        setUp(() {
          when(() => httpClient.send(any())).thenThrow(exception);
        });

        test('throws CacheUpdateFailure', () async {
          await expectLater(
            runWithOverrides(cache.updateAll),
            throwsA(
              isA<CacheUpdateFailure>().having(
                (e) => e.message,
                'message',
                contains('Failed to download patch: $exception'),
              ),
            ),
          );
        });

        test('retries and log', () async {
          await expectLater(
            runWithOverrides(cache.updateAll),
            throwsA(
              isA<CacheUpdateFailure>(),
            ),
          );

          verify(
            () => logger.detail('Failed to update patch, retrying...'),
          ).called(2); // once per required artifact
        });

        test('deletes artifact directory if it exists', () async {
          final patchArtifactDirectory = runWithOverrides(
            () => cache.getArtifactDirectory('patch'),
          )..createSync(recursive: true);
          expect(patchArtifactDirectory.existsSync(), isTrue);
          await expectLater(
            runWithOverrides(cache.updateAll),
            throwsA(
              isA<CacheUpdateFailure>(),
            ),
          );
          expect(patchArtifactDirectory.existsSync(), isFalse);
        });
      });

      test('throws CacheUpdateFailure if a non-200 is returned', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.notFound,
            reasonPhrase: 'Not Found',
          ),
        );
        await expectLater(
          runWithOverrides(cache.updateAll),
          throwsA(
            isA<CacheUpdateFailure>().having(
              (e) => e.message,
              'message',
              contains('Failed to download patch: 404 Not Found'),
            ),
          ),
        );
      });

      test('skips optional artifacts if a 404 is returned', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (invocation) async {
            final request =
                invocation.positionalArguments.first as http.BaseRequest;
            final fileName = p.basename(request.url.path);
            if (fileName.startsWith('aot-tools')) {
              return http.StreamedResponse(
                const Stream.empty(),
                HttpStatus.notFound,
                reasonPhrase: 'Not Found',
              );
            }
            return http.StreamedResponse(
              Stream.value(ZipEncoder().encode(Archive())!),
              HttpStatus.ok,
            );
          },
        );
        await expectLater(
          runWithOverrides(cache.updateAll),
          completes,
        );
        verify(
          () => logger.detail(
            '''[cache] optional artifact: "aot-tools.dill" was not found, skipping...''',
          ),
        ).called(1);
      });

      test('downloads correct artifacts', () async {
        final patchArtifactDirectory = runWithOverrides(
          () => cache.getArtifactDirectory('patch'),
        );
        expect(patchArtifactDirectory.existsSync(), isFalse);
        await expectLater(runWithOverrides(cache.updateAll), completes);
        expect(patchArtifactDirectory.existsSync(), isTrue);
      });

      group('when checksum validation fails', () {
        setUp(() {
          when(
            () => checksumChecker.checkFile(
              any(),
              checksum: any(named: 'checksum'),
              algorithm: any(named: 'algorithm'),
            ),
          ).thenReturn(false);
        });

        test('fails with the correct message', () async {
          await expectLater(
            () => runWithOverrides(cache.updateAll),
            throwsA(
              isA<CacheUpdateFailure>().having(
                (e) => e.message,
                'message',
                contains(
                  'Failed to download bundletool.jar: checksum mismatch',
                ),
              ),
            ),
          );
        });
      });

      test('pull correct artifact for MacOS', () async {
        setMockPlatform(Platform.macOS);

        await expectLater(runWithOverrides(cache.updateAll), completes);

        final requests = verify(() => httpClient.send(captureAny()))
            .captured
            .cast<http.BaseRequest>()
            .map((r) => r.url)
            .toList();

        String perEngine(String name) =>
            '${cache.storageBaseUrl}/${cache.storageBucket}/shorebird/$shorebirdEngineRevision/$name';

        final expected = [
          perEngine('patch-darwin-x64.zip'),
          'https://github.com/google/bundletool/releases/download/1.15.6/bundletool-all-1.15.6.jar',
          perEngine('aot-tools.dill'),
        ].map(Uri.parse).toList();

        expect(requests, equals(expected));
      });

      test('pull correct artifact for Windows', () async {
        setMockPlatform(Platform.windows);

        await expectLater(runWithOverrides(cache.updateAll), completes);

        final requests = verify(() => httpClient.send(captureAny()))
            .captured
            .cast<http.BaseRequest>()
            .map((r) => r.url)
            .toList();

        String perEngine(String name) =>
            '${cache.storageBaseUrl}/${cache.storageBucket}/shorebird/$shorebirdEngineRevision/$name';

        final expected = [
          perEngine('patch-windows-x64.zip'),
          'https://github.com/google/bundletool/releases/download/1.15.6/bundletool-all-1.15.6.jar',
          perEngine('aot-tools.dill'),
        ].map(Uri.parse).toList();

        expect(requests, equals(expected));
      });

      test('pull correct artifact for Linux', () async {
        setMockPlatform(Platform.linux);

        await expectLater(runWithOverrides(cache.updateAll), completes);

        final requests = verify(() => httpClient.send(captureAny()))
            .captured
            .cast<http.BaseRequest>()
            .map((r) => r.url)
            .toList();

        String perEngine(String name) =>
            '${cache.storageBaseUrl}/${cache.storageBucket}/shorebird/$shorebirdEngineRevision/$name';

        final expected = [
          perEngine('patch-linux-x64.zip'),
          'https://github.com/google/bundletool/releases/download/1.15.6/bundletool-all-1.15.6.jar',
          perEngine('aot-tools.dill'),
        ].map(Uri.parse).toList();

        expect(requests, equals(expected));
      });
    });
  });

  group(CachedArtifact, () {
    late Cache cache;
    late ChecksumChecker checksumChecker;
    late ShorebirdLogger logger;
    late Platform platform;
    late _TestCachedArtifact cachedArtifact;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          checksumCheckerRef.overrideWith(() => checksumChecker),
          loggerRef.overrideWith(() => logger),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(File(''));
    });

    setUp(() {
      cache = MockCache();
      checksumChecker = MockChecksumChecker();
      logger = MockShorebirdLogger();
      platform = MockPlatform();
      cachedArtifact = _TestCachedArtifact(cache: cache, platform: platform);
    });

    group('isValid', () {
      group('when the artifact file does not exist', () {
        test('returns false', () async {
          expect(await runWithOverrides(cachedArtifact.isValid), isFalse);
        });
      });

      group('when the artifact file exists', () {
        setUp(() {
          cachedArtifact.file.createSync(recursive: true);
        });

        group('when there is no expected checksum', () {
          setUp(() {
            cachedArtifact.checksumOverride = null;
          });

          test('returns true', () async {
            expect(await runWithOverrides(cachedArtifact.isValid), isTrue);
          });
        });

        group('when there is an expected checksum', () {
          setUp(() {
            cachedArtifact.checksumOverride = 'some-checksum';
          });

          group('when the checksum matches', () {
            setUp(() {
              when(
                () => checksumChecker.checkFile(
                  any(),
                  checksum: any(named: 'checksum'),
                  algorithm: any(named: 'algorithm'),
                ),
              ).thenReturn(true);
            });

            test('returns true', () async {
              expect(await runWithOverrides(cachedArtifact.isValid), isTrue);
            });
          });

          group('when the checksum does not match', () {
            setUp(() {
              when(
                () => checksumChecker.checkFile(
                  any(),
                  checksum: any(named: 'checksum'),
                  algorithm: any(named: 'algorithm'),
                ),
              ).thenReturn(false);
            });

            test('returns false', () async {
              expect(
                await runWithOverrides(cachedArtifact.isValid),
                isFalse,
              );
            });
          });
        });
      });
    });
  });
}

class _TestCachedArtifact extends CachedArtifact {
  _TestCachedArtifact({required super.cache, required super.platform});

  String? checksumOverride;

  @override
  String? get sha256Checksum => checksumOverride;

  final Directory _location = Directory.systemTemp.createTempSync();

  @override
  bool get isExecutable => throw UnimplementedError();

  @override
  String get fileName => 'test_artifact.exe';

  @override
  File get file => File(p.join(_location.path, fileName));

  @override
  String get storageUrl => throw UnimplementedError();
}

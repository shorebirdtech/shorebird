import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
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

    late Directory shorebirdRoot;
    late http.Client httpClient;
    late Logger logger;
    late Platform platform;
    late Process chmodProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess shorebirdProcess;
    late Cache cache;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          cacheRef.overrideWith(() => cache),
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
      registerFallbackValue(FakeBaseRequest());
    });

    setUp(() {
      httpClient = MockHttpClient();
      logger = MockLogger();
      platform = MockPlatform();
      chmodProcess = MockProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdProcess = MockShorebirdProcess();

      shorebirdRoot = Directory.systemTemp.createTempSync();
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
        runWithOverrides(cache.clear);
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
      group('patch', () {
        test('throws CacheUpdateFailure if a SocketException is thrown',
            () async {
          const exception = SocketException('test');
          when(() => httpClient.send(any())).thenThrow(exception);
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
          verify(
            () => logger.detail(
              '''[cache] optional artifact: "aot-tools" was not found, skipping...''',
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

        test('aot-tools falls back to executable', () async {
          setMockPlatform(Platform.macOS);

          when(() => httpClient.send(any())).thenAnswer(
            (invocation) async {
              final request =
                  invocation.positionalArguments.first as http.BaseRequest;
              final fileName = p.basename(request.url.path);
              if (fileName == 'aot-tools.dill') {
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
            // Requests the .dill, fails and falls back to executable:
            perEngine('aot-tools.dill'),
            perEngine('aot-tools-darwin-x64'),
          ].map(Uri.parse).toList();

          expect(requests, equals(expected));
        });

        test('aot-tools executable paths by platform', () async {
          setMockPlatform(Platform.windows);
          expect(
            runWithOverrides(
              () => AotToolsExeArtifact(cache: cache, platform: platform)
                  .storageUrl,
            ),
            endsWith('aot-tools-windows-x64'),
          );
          setMockPlatform(Platform.linux);
          expect(
            runWithOverrides(
              () => AotToolsExeArtifact(cache: cache, platform: platform)
                  .storageUrl,
            ),
            endsWith('aot-tools-linux-x64'),
          );
          setMockPlatform(Platform.macOS);
          expect(
            runWithOverrides(
              () => AotToolsExeArtifact(cache: cache, platform: platform)
                  .storageUrl,
            ),
            endsWith('aot-tools-darwin-x64'),
          );
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
  });
}

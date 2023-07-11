import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:test/test.dart';

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockPlatform extends Mock implements Platform {}

class TestCachedArtifact extends CachedArtifact {
  TestCachedArtifact({required super.cache, required super.platform});

  @override
  String get name => 'test';

  @override
  String get storageUrl => 'test-url';
}

void main() {
  group('Cache', () {
    late Directory shorebirdRoot;
    late http.Client httpClient;
    late Platform platform;
    late Cache cache;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          cacheRef.overrideWith(() => cache),
          platformRef.overrideWith(() => platform),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(_FakeBaseRequest());
    });

    setUp(() {
      httpClient = _MockHttpClient();
      platform = _MockPlatform();

      shorebirdRoot = Directory.systemTemp.createTempSync();
      ShorebirdEnvironment.shorebirdEngineRevision = 'test-revision';

      when(() => platform.environment).thenReturn({});
      when(() => platform.isMacOS).thenReturn(true);
      when(() => platform.isWindows).thenReturn(false);
      when(() => platform.isLinux).thenReturn(false);
      when(() => platform.script).thenReturn(
        Uri.file(
          p.join(
            shorebirdRoot.path,
            'bin',
            'cache',
            'shorebird.snapshot',
          ),
        ),
      );

      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(ZipEncoder().encode(Archive())!),
          HttpStatus.ok,
        ),
      );

      cache = Cache(httpClient: httpClient, platform: platform);
    });

    test('can be instantiated w/out args', () {
      expect(Cache.new, returnsNormally);
    });

    group('getArtifactDirectory', () {
      test('returns correct directory', () {
        final directory = cache.getArtifactDirectory('test');
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
        final directory = cache.getPreviewDirectory('test');
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

    group('CachedArtifact', () {
      late CachedArtifact artifact;

      setUp(() {
        artifact = TestCachedArtifact(cache: cache, platform: platform);
      });

      test('has empty executables by default', () {
        expect(artifact.executables, isEmpty);
      });
    });

    group('clear', () {
      test('deletes the cache directory', () async {
        final shorebirdCacheDirectory =
            runWithOverrides(() => Cache.shorebirdCacheDirectory)
              ..createSync(recursive: true);
        expect(shorebirdCacheDirectory.existsSync(), isTrue);
        runWithOverrides(cache.clear);
        expect(shorebirdCacheDirectory.existsSync(), isFalse);
      });

      test('does nothing if directory does not exist', () {
        final shorebirdCacheDirectory =
            runWithOverrides(() => Cache.shorebirdCacheDirectory);
        expect(shorebirdCacheDirectory.existsSync(), isFalse);
        runWithOverrides(cache.clear);
        expect(shorebirdCacheDirectory.existsSync(), isFalse);
      });
    });

    group('updateAll', () {
      group('patch', () {
        test('downloads correct artifacts', () async {
          final patchArtifactDirectory = runWithOverrides(
            () => cache.getArtifactDirectory('patch'),
          );
          expect(patchArtifactDirectory.existsSync(), isFalse);
          await expectLater(runWithOverrides(cache.updateAll), completes);
          expect(patchArtifactDirectory.existsSync(), isTrue);
        });

        test('pull correct artifact for MacOS', () async {
          when(() => platform.isMacOS).thenReturn(true);
          when(() => platform.isWindows).thenReturn(false);
          when(() => platform.isLinux).thenReturn(false);

          await expectLater(runWithOverrides(cache.updateAll), completes);

          final request = verify(() => httpClient.send(captureAny()))
              .captured
              .first as http.BaseRequest;

          expect(
            request.url,
            equals(
              Uri.parse(
                '${cache.storageBaseUrl}/${cache.storageBucket}/shorebird/${ShorebirdEnvironment.shorebirdEngineRevision}/patch-darwin-x64.zip',
              ),
            ),
          );
        });

        test('pull correct artifact for Windows', () async {
          when(() => platform.isMacOS).thenReturn(false);
          when(() => platform.isWindows).thenReturn(true);
          when(() => platform.isLinux).thenReturn(false);

          await expectLater(runWithOverrides(cache.updateAll), completes);

          final request = verify(() => httpClient.send(captureAny()))
              .captured
              .first as http.BaseRequest;

          expect(
            request.url,
            equals(
              Uri.parse(
                '${cache.storageBaseUrl}/${cache.storageBucket}/shorebird/${ShorebirdEnvironment.shorebirdEngineRevision}/patch-windows-x64.zip',
              ),
            ),
          );
        });

        test('pull correct artifact for Linux', () async {
          when(() => platform.isMacOS).thenReturn(false);
          when(() => platform.isWindows).thenReturn(false);
          when(() => platform.isLinux).thenReturn(true);

          await expectLater(runWithOverrides(cache.updateAll), completes);

          final request = verify(() => httpClient.send(captureAny()))
              .captured
              .first as http.BaseRequest;
          expect(
            request.url,
            equals(
              Uri.parse(
                '${cache.storageBaseUrl}/${cache.storageBucket}/shorebird/${ShorebirdEnvironment.shorebirdEngineRevision}/patch-linux-x64.zip',
              ),
            ),
          );
        });
      });
    });
  });
}

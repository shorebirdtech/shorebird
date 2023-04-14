import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/engine_revision.dart';
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
  String get storagePath => 'test-path';
}

void main() {
  group('Cache', () {
    late Directory shorebirdRoot;
    late http.Client httpClient;
    late Platform platform;
    late Cache cache;

    setUpAll(() {
      registerFallbackValue(_FakeBaseRequest());
    });

    setUp(() {
      httpClient = _MockHttpClient();
      platform = _MockPlatform();

      shorebirdRoot = Directory.systemTemp.createTempSync();
      ShorebirdEnvironment.platform = platform;

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
        Cache.shorebirdCacheDirectory.createSync(recursive: true);
        expect(Cache.shorebirdCacheDirectory.existsSync(), isTrue);
        cache.clear();
        expect(Cache.shorebirdCacheDirectory.existsSync(), isFalse);
      });

      test('does nothing if directory does not exist', () {
        expect(Cache.shorebirdCacheDirectory.existsSync(), isFalse);
        cache.clear();
        expect(Cache.shorebirdCacheDirectory.existsSync(), isFalse);
      });
    });

    group('updateAll', () {
      group('patch', () {
        test('downloads correct artifacts', () async {
          expect(cache.getArtifactDirectory('patch').existsSync(), isFalse);
          await expectLater(cache.updateAll(), completes);
          expect(cache.getArtifactDirectory('patch').existsSync(), isTrue);
        });

        test('pull correct artifact for MacOS', () async {
          when(() => platform.isMacOS).thenReturn(true);
          when(() => platform.isWindows).thenReturn(false);
          when(() => platform.isLinux).thenReturn(false);

          await expectLater(cache.updateAll(), completes);
          final request = verify(() => httpClient.send(captureAny()))
              .captured
              .first as http.BaseRequest;

          expect(
            request.url,
            equals(
              Uri.parse(
                '${cache.storageBaseUrl}/${cache.storageBucket}/shorebird/$shorebirdEngineRevision/patch-darwin-x64.zip',
              ),
            ),
          );
        });

        test('pull correct artifact for Windows', () async {
          when(() => platform.isMacOS).thenReturn(false);
          when(() => platform.isWindows).thenReturn(true);
          when(() => platform.isLinux).thenReturn(false);

          await expectLater(cache.updateAll(), completes);
          final request = verify(() => httpClient.send(captureAny()))
              .captured
              .first as http.BaseRequest;

          expect(
            request.url,
            equals(
              Uri.parse(
                '${cache.storageBaseUrl}/${cache.storageBucket}/shorebird/$shorebirdEngineRevision/patch-windows-x64.zip',
              ),
            ),
          );
        });

        test('pull correct artifact for Linux', () async {
          when(() => platform.isMacOS).thenReturn(false);
          when(() => platform.isWindows).thenReturn(false);
          when(() => platform.isLinux).thenReturn(true);

          await expectLater(cache.updateAll(), completes);
          final request = verify(() => httpClient.send(captureAny()))
              .captured
              .first as http.BaseRequest;

          expect(
            request.url,
            equals(
              Uri.parse(
                '${cache.storageBaseUrl}/${cache.storageBucket}/shorebird/$shorebirdEngineRevision/patch-linux-x64.zip',
              ),
            ),
          );
        });
      });
    });
  });
}

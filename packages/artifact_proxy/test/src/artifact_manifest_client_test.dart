import 'dart:io';

import 'package:artifact_proxy/artifact_proxy.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('ArtifactsManifestClient', () {
    const revision = '8b89f8bd9fc6982aa9c4557fd0e5e89db1ff9986';
    late http.Client httpClient;
    late ArtifactManifestClient client;

    setUpAll(() {
      registerFallbackValue(Uri());
    });

    setUp(() {
      httpClient = _MockHttpClient();
      client = ArtifactManifestClient(httpClient: httpClient);

      when(() => httpClient.get(any())).thenAnswer((_) async {
        return http.Response(_testArtifactManifest, HttpStatus.ok);
      });
    });

    test('can be instantiated without an explicit http client', () {
      expect(ArtifactManifestClient.new, returnsNormally);
    });

    test('makes correct http request to storage bucket', () async {
      client.getManifest(revision).ignore();

      verify(
        () => httpClient.get(
          Uri.parse(
            'https://storage.googleapis.com/download.shorebird.dev/shorebird/$revision/artifacts_manifest.yaml',
          ),
        ),
      ).called(1);
    });

    test('throws when manifest does not exist', () async {
      when(() => httpClient.get(any())).thenAnswer((_) async {
        return http.Response('', HttpStatus.notFound);
      });
      await expectLater(client.getManifest(revision), throwsException);
    });

    test('returns manifest when exists', () async {
      await expectLater(
        client.getManifest(revision),
        completion(isA<ArtifactsManifest>()),
      );
    });

    test('cached manifest', () async {
      await expectLater(
        client.getManifest(revision),
        completion(isA<ArtifactsManifest>()),
      );
      await expectLater(
        client.getManifest(revision),
        completion(isA<ArtifactsManifest>()),
      );
      verify(
        () => httpClient.get(
          Uri.parse(
            'https://storage.googleapis.com/download.shorebird.dev/shorebird/$revision/artifacts_manifest.yaml',
          ),
        ),
      ).called(1);
    });
  });
}

const _testArtifactManifest = r'''
flutter_engine_revision: ec975089acb540fc60752606a3d3ba809dd1528b
storage_bucket: https://download.shorebird.dev
artifact_overrides:
  # artifacts.zip
  - flutter_infra_release/flutter/$engine/android-arm-64-release/artifacts.zip
  - flutter_infra_release/flutter/$engine/android-arm-release/artifacts.zip
  - flutter_infra_release/flutter/$engine/android-x64-release/artifacts.zip
  # embedding release
  - download.flutter.io/io/flutter/flutter_embedding_release/1.0.0-$engine/flutter_embedding_release-1.0.0-$engine.pom
  - download.flutter.io/io/flutter/flutter_embedding_release/1.0.0-$engine/flutter_embedding_release-1.0.0-$engine.jar
  # arm64_v8a release
  - download.flutter.io/io/flutter/arm64_v8a_release/1.0.0-$engine/arm64_v8a_release-1.0.0-$engine.pom
  - download.flutter.io/io/flutter/arm64_v8a_release/1.0.0-$engine/arm64_v8a_release-1.0.0-$engine.jar
  # armeabi_v7a release
  - download.flutter.io/io/flutter/armeabi_v7a_release/1.0.0-$engine/armeabi_v7a_release-1.0.0-$engine.pom
  - download.flutter.io/io/flutter/armeabi_v7a_release/1.0.0-$engine/armeabi_v7a_release-1.0.0-$engine.jar
  # x86_64 release
  - download.flutter.io/io/flutter/x86_64_release/1.0.0-$engine/x86_64_release-1.0.0-$engine.pom
  - download.flutter.io/io/flutter/x86_64_release/1.0.0-$engine/x86_64_release-1.0.0-$engine.jar
''';

import 'dart:io';

import 'package:artifact_proxy/artifact_proxy.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _MockArtifactManifestClient extends Mock
    implements ArtifactManifestClient {}

void main() {
  const shorebirdEngineRevision = '8b89f8bd9fc6982aa9c4557fd0e5e89db1ff9986';
  const manifest = ArtifactsManifest(
    flutterEngineRevision: 'ec975089acb540fc60752606a3d3ba809dd1528b',
    storageBucket: 'download.shorebird.dev',
    artifactOverrides: {
      r'flutter_infra_release/flutter/$engine/android-arm-64-release/artifacts.zip',
      r'flutter_infra_release/flutter/$engine/android-arm-release/artifacts.zip',
      r'flutter_infra_release/flutter/$engine/android-x64-release/artifacts.zip',
      r'download.flutter.io/io/flutter/flutter_embedding_release/1.0.0-$engine/flutter_embedding_release-1.0.0-$engine.pom',
      r'download.flutter.io/io/flutter/flutter_embedding_release/1.0.0-$engine/flutter_embedding_release-1.0.0-$engine.jar',
      r'download.flutter.io/io/flutter/arm64_v8a_release/1.0.0-$engine/arm64_v8a_release-1.0.0-$engine.pom',
      r'download.flutter.io/io/flutter/arm64_v8a_release/1.0.0-$engine/arm64_v8a_release-1.0.0-$engine.jar',
      r'download.flutter.io/io/flutter/armeabi_v7a_release/1.0.0-$engine/armeabi_v7a_release-1.0.0-$engine.pom',
      r'download.flutter.io/io/flutter/armeabi_v7a_release/1.0.0-$engine/armeabi_v7a_release-1.0.0-$engine.jar',
      r'download.flutter.io/io/flutter/x86_64_release/1.0.0-$engine/x86_64_release-1.0.0-$engine.pom',
      r'download.flutter.io/io/flutter/x86_64_release/1.0.0-$engine/x86_64_release-1.0.0-$engine.jar',
    },
  );

  Request buildRequest(String path) {
    return Request('GET', Uri.parse('http://localhost').replace(path: path));
  }

  Matcher isRedirectTo(String location) {
    return isA<Response>()
        .having((r) => r.statusCode, 'status code', HttpStatus.found)
        .having((r) => r.headers['location'], 'location', location);
  }

  group('artifactProxy', () {
    late ArtifactManifestClient client;
    late Handler handler;

    setUp(() {
      client = _MockArtifactManifestClient();
      handler = artifactProxyHandler(client: client);

      when(() => client.getManifest(any())).thenAnswer((_) async => manifest);
    });

    test('should return 404 when no manifest is found', () async {
      const path =
          'flutter_infra_release/flutter/$shorebirdEngineRevision/android-x64-release/artifacts.zip';
      when(() => client.getManifest(any())).thenThrow(Exception('oops'));
      final request = buildRequest(path);
      final response = await handler(request);
      expect(response.statusCode, equals(HttpStatus.notFound));
      verify(() => client.getManifest(shorebirdEngineRevision)).called(1);
    });

    test(
        'should proxy to Flutter artifacts '
        'when no engine revision is detected', () async {
      const path =
          'flutter_infra_release/flutter/fonts/3012db47f3130e62f7cc0beabff968a33cbec8d8/fonts.zip';
      final request = buildRequest(path);
      final response = await handler(request);
      expect(
        response,
        isRedirectTo('https://storage.googleapis.com/$path'),
      );
      verifyNever(() => client.getManifest(any()));
    });

    test(
        'should proxy to Shorebird artifacts '
        'when an engine revision is detected', () async {
      const path =
          'flutter_infra_release/flutter/$shorebirdEngineRevision/android-x64-release/artifacts.zip';
      final request = buildRequest(path);
      final response = await handler(request);
      expect(
        response,
        isRedirectTo(
          'https://storage.googleapis.com/${manifest.storageBucket}/$path',
        ),
      );
      verify(() => client.getManifest(shorebirdEngineRevision)).called(1);
    });

    test(
        'should return 404 '
        'when pattern is not recognized', () async {
      const path =
          'flutter_infra_release/flutter/$shorebirdEngineRevision/unknown/artifacts.zip';
      final request = buildRequest(path);
      final response = await handler(request);
      expect(response.statusCode, equals(HttpStatus.notFound));
      verifyNever(() => client.getManifest(shorebirdEngineRevision));
    });

    test(
        'should proxy to Flutter '
        'when no override is found '
        'and path is chrome infra', () async {
      const path =
          'flutter_infra_release/cipd/flutter/web/canvaskit_bundle/+/ztaLvbs5GPmlAwUosC7VVp7EQnNVknRpNuKdv7vmzaAC';
      final request = buildRequest(path);
      final response = await handler(request);
      expect(
        response,
        isRedirectTo(
          'https://chrome-infra-packages.appspot.com/dl/flutter/web/canvaskit_bundle/+/ztaLvbs5GPmlAwUosC7VVp7EQnNVknRpNuKdv7vmzaAC',
        ),
      );
      verifyNever(() => client.getManifest(any()));
    });
  });
}

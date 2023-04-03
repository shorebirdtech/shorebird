import 'dart:io';

import 'package:artifact_proxy/artifact_proxy.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  const shorebirdEngineRevision = 'ff32625d5bda6d3eb2eb131e30a4c26ed4960002';
  const flutterEngineRevision = 'ec975089acb540fc60752606a3d3ba809dd1528b';
  const shorebirdStorageBucket = 'download.shorebird.dev';
  const config = {
    'engine_mappings': {
      shorebirdEngineRevision: {
        'flutter_engine_revision': flutterEngineRevision,
        'shorebird_storage_bucket': shorebirdStorageBucket,
        'shorebird_artifact_overrides': [
          r'flutter_infra_release/flutter/$engine/android-x64-release/artifacts.zip'
        ]
      }
    }
  };

  Request buildRequest(String path) {
    return Request('GET', Uri.parse('http://localhost').replace(path: path));
  }

  Matcher isRedirectTo(String location) {
    return isA<Response>()
        .having((r) => r.statusCode, 'status code', HttpStatus.found)
        .having((r) => r.headers['location'], 'location', location);
  }

  group('artifactProxy', () {
    test(
        'should proxy to Flutter artifacts '
        'when no engine revision is detected', () async {
      const path = 'path/with/no/revision/foo.zip';
      final handler = artifactProxyHandler(config: config);
      final request = buildRequest(path);
      final response = await handler(request);
      expect(
        response,
        isRedirectTo('https://storage.googleapis.com/$path'),
      );
    });

    test(
        'should proxy to Shorebird artifacts '
        'when an engine revision is detected', () async {
      const path =
          'flutter_infra_release/flutter/$shorebirdEngineRevision/android-x64-release/artifacts.zip';
      final handler = artifactProxyHandler(config: config);
      final request = buildRequest(path);
      final response = await handler(request);
      expect(
        response,
        isRedirectTo(
          'https://storage.googleapis.com/$shorebirdStorageBucket/$path',
        ),
      );
    });

    test(
        'should proxy to Flutter '
        'when no shorebird override is found', () async {
      const path =
          'flutter_infra_release/flutter/$shorebirdEngineRevision/unknown/artifacts.zip';
      final handler = artifactProxyHandler(config: config);
      final request = buildRequest(path);
      final response = await handler(request);
      expect(
        response,
        isRedirectTo(
          'https://storage.googleapis.com/${path.replaceFirst(shorebirdEngineRevision, flutterEngineRevision)}',
        ),
      );
    });

    test(
        'should proxy to Flutter '
        'when no shorebird override is found '
        'and path is chrome infra', () async {
      const path =
          '/flutter_infra_release/cipd/flutter/web/canvaskit_bundle/+/ztaLvbs5GPmlAwUosC7VVp7EQnNVknRpNuKdv7vmzaAC';
      final handler = artifactProxyHandler(config: config);
      final request = buildRequest(path);
      final response = await handler(request);
      expect(
        response,
        isRedirectTo(
          'https://chrome-infra-packages.appspot.com/dl/flutter/web/canvaskit_bundle/+/ztaLvbs5GPmlAwUosC7VVp7EQnNVknRpNuKdv7vmzaAC',
        ),
      );
    });
  });
}

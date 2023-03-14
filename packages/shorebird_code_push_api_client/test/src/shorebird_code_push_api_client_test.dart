// ignore_for_file: prefer_const_constructors
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:shorebird_code_push_api_client/shorebird_code_push_api_client.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

void main() {
  group('ShorebirdCodePushApiClient', () {
    const apiKey = 'api-key';
    const productId = 'shorebird-example';

    late http.Client httpClient;
    late ShorebirdCodePushApiClient shorebirdCodePushApiClient;

    setUpAll(() {
      registerFallbackValue(_FakeBaseRequest());
      registerFallbackValue(Uri());
    });

    setUp(() {
      httpClient = _MockHttpClient();
      shorebirdCodePushApiClient = ShorebirdCodePushApiClient(
        apiKey: apiKey,
        httpClient: httpClient,
      );
    });

    test('can be instantiated', () {
      expect(ShorebirdCodePushApiClient(apiKey: apiKey), isNotNull);
    });

    group('createApp', () {
      test('throws an exception if the http request fails', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('', HttpStatus.badRequest));

        expect(
          shorebirdCodePushApiClient.createApp(productId: productId),
          throwsA(isA<Exception>()),
        );
      });

      test('completes when request succeeds', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('', HttpStatus.created));

        await shorebirdCodePushApiClient.createApp(productId: productId);

        final uri = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).captured.single as Uri;

        expect(
          uri,
          shorebirdCodePushApiClient.hostedUri.replace(path: '/api/v1/apps'),
        );
      });
    });

    group('createPatch', () {
      test('throws an exception if the http request fails', () async {
        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.empty(),
            400,
          );
        });

        expect(
          shorebirdCodePushApiClient.createPatch(
            artifactPath: path.join('test', 'fixtures', 'release.txt'),
            baseVersion: '1.0.0',
            productId: 'shorebird-example',
            channel: 'stable',
          ),
          throwsA(isA<Exception>()),
        );
      });

      test('sends a multipart request to the correct url', () async {
        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.empty(),
            HttpStatus.created,
          );
        });

        await shorebirdCodePushApiClient.createPatch(
          artifactPath: path.join('test', 'fixtures', 'release.txt'),
          baseVersion: '1.0.0',
          productId: 'shorebird-example',
          channel: 'stable',
        );

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.MultipartRequest;
        expect(
          request.url,
          shorebirdCodePushApiClient.hostedUri.replace(path: '/api/v1/patches'),
        );
      });
    });

    group('deleteApp', () {
      test('throws an exception if the http request fails', () async {
        when(
          () => httpClient.delete(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) async => http.Response('', HttpStatus.badRequest));

        expect(
          shorebirdCodePushApiClient.deleteApp(productId: productId),
          throwsA(isA<Exception>()),
        );
      });

      test('completes when request succeeds', () async {
        when(
          () => httpClient.delete(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) async => http.Response('', HttpStatus.noContent));

        await shorebirdCodePushApiClient.deleteApp(productId: productId);

        final uri = verify(
          () => httpClient.delete(
            captureAny(),
            headers: any(named: 'headers'),
          ),
        ).captured.single as Uri;

        expect(
          uri,
          shorebirdCodePushApiClient.hostedUri.replace(
            path: '/api/v1/apps/$productId',
          ),
        );
      });
    });

    group('downloadEngine', () {
      const engineRevision = 'engine-revision';
      test('throws an exception if the http request fails', () async {
        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.empty(),
            400,
          );
        });

        expect(
          shorebirdCodePushApiClient.downloadEngine(engineRevision),
          throwsA(isA<Exception>()),
        );
      });

      test('sends a request to the correct url', () async {
        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.empty(),
            HttpStatus.ok,
          );
        });

        await shorebirdCodePushApiClient.downloadEngine(engineRevision);

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.Request;

        expect(
          request.url,
          Uri.parse(
            'https://storage.googleapis.com/code-push-dev.appspot.com/engines/dev/engine.zip',
          ),
        );
      });
    });

    group('close', () {
      test('closes the underlying client', () {
        shorebirdCodePushApiClient.close();
        verify(() => httpClient.close()).called(1);
      });
    });
  });
}

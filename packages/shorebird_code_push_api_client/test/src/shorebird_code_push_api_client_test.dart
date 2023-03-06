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

    late http.Client httpClient;
    late ShorebirdCodePushApiClient shorebirdCodePushApiClient;

    setUpAll(() {
      registerFallbackValue(_FakeBaseRequest());
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

    group('createRelease', () {
      test('throws an exception if the http request fails', () async {
        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.empty(),
            400,
          );
        });

        expect(
          shorebirdCodePushApiClient.createRelease(
            path.join('test', 'fixtures', 'release.txt'),
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

        await shorebirdCodePushApiClient.createRelease(
          path.join('test', 'fixtures', 'release.txt'),
        );

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.MultipartRequest;
        expect(
          request.url,
          Uri.parse(
            'https://shorebird-code-push-api-cypqazu4da-uc.a.run.app/api/v1/releases',
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
            'https://shorebird-code-push-api-cypqazu4da-uc.a.run.app/api/v1/engines/$engineRevision',
          ),
        );
      });
    });
  });
}

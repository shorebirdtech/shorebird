// ignore_for_file: prefer_const_constructors
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

void main() {
  group('CodePushClient', () {
    const apiKey = 'api-key';
    const appId = 'shorebird-example';
    const errorResponse = ErrorResponse(
      code: 'test_code',
      message: 'test message',
      details: 'test details',
    );

    late http.Client httpClient;
    late CodePushClient codePushClient;

    setUpAll(() {
      registerFallbackValue(_FakeBaseRequest());
      registerFallbackValue(Uri());
    });

    setUp(() {
      httpClient = _MockHttpClient();
      codePushClient = CodePushClient(
        apiKey: apiKey,
        httpClient: httpClient,
      );
    });

    test('can be instantiated', () {
      expect(CodePushClient(apiKey: apiKey), isNotNull);
    });

    group('CodePushException', () {
      test('toString is correct', () {
        const exceptionWithDetails = CodePushException(
          message: 'message',
          details: 'details',
        );
        const exceptionWithoutDetails = CodePushException(message: 'message');

        expect(exceptionWithDetails.toString(), 'message\ndetails');
        expect(exceptionWithoutDetails.toString(), 'message');
      });
    });

    group('createApp', () {
      test('throws an exception if the http request fails (unknown)', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('', HttpStatus.badRequest));

        expect(
          codePushClient.createApp(appId: appId),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessage,
            ),
          ),
        );
      });

      test('throws an exception if the http request fails', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            json.encode(errorResponse.toJson()),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.createApp(appId: appId),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              errorResponse.message,
            ),
          ),
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

        await codePushClient.createApp(appId: appId);

        final uri = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).captured.single as Uri;

        expect(
          uri,
          codePushClient.hostedUri.replace(path: '/api/v1/apps'),
        );
      });
    });

    group('createPatch', () {
      test('throws an exception if the http request fails (unknown)', () async {
        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.empty(),
            HttpStatus.failedDependency,
          );
        });

        expect(
          codePushClient.createPatch(
            artifactPath: fixture.path,
            releaseVersion: '1.0.0',
            appId: 'shorebird-example',
            channel: 'stable',
          ),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessage,
            ),
          ),
        );
      });

      test('throws an exception if the http request fails', () async {
        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          );
        });

        expect(
          codePushClient.createPatch(
            artifactPath: fixture.path,
            releaseVersion: '1.0.0',
            appId: 'shorebird-example',
            channel: 'stable',
          ),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              errorResponse.message,
            ),
          ),
        );
      });

      test('sends a multipart request to the correct url', () async {
        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();
        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.empty(),
            HttpStatus.created,
          );
        });

        await codePushClient.createPatch(
          artifactPath: fixture.path,
          releaseVersion: '1.0.0',
          appId: 'shorebird-example',
          channel: 'stable',
        );

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.MultipartRequest;

        expect(
          request.url,
          codePushClient.hostedUri.replace(path: '/api/v1/patches'),
        );
      });
    });

    group('deleteApp', () {
      test('throws an exception if the http request fails (unknown)', () async {
        when(
          () => httpClient.delete(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response('', HttpStatus.failedDependency),
        );

        expect(
          codePushClient.deleteApp(appId: appId),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessage,
            ),
          ),
        );
      });

      test('throws an exception if the http request fails', () async {
        when(
          () => httpClient.delete(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            json.encode(errorResponse.toJson()),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.deleteApp(appId: appId),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              errorResponse.message,
            ),
          ),
        );
      });

      test('completes when request succeeds', () async {
        when(
          () => httpClient.delete(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) async => http.Response('', HttpStatus.noContent));

        await codePushClient.deleteApp(appId: appId);

        final uri = verify(
          () => httpClient.delete(
            captureAny(),
            headers: any(named: 'headers'),
          ),
        ).captured.single as Uri;

        expect(
          uri,
          codePushClient.hostedUri.replace(
            path: '/api/v1/apps/$appId',
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
            HttpStatus.badRequest,
          );
        });

        expect(
          codePushClient.downloadEngine(engineRevision),
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

        await codePushClient.downloadEngine(engineRevision);

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.Request;

        expect(
          request.url,
          equals(
            codePushClient.hostedUri.replace(
              path: '/api/v1/engines/$engineRevision',
            ),
          ),
        );
      });
    });

    group('getApps', () {
      test('throws an exception if the http request fails (unknown)', () async {
        when(
          () => httpClient.get(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            '',
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.getApps(),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessage,
            ),
          ),
        );
      });

      test('throws an exception if the http request fails', () async {
        when(
          () => httpClient.get(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            json.encode(errorResponse.toJson()),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.getApps(),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              errorResponse.message,
            ),
          ),
        );
      });

      test('completes when request succeeds (empty)', () async {
        when(
          () => httpClient.get(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(json.encode([]), HttpStatus.ok),
        );

        final apps = await codePushClient.getApps();
        expect(apps, isEmpty);
      });

      test('completes when request succeeds (populated)', () async {
        final expected = [
          App(appId: 'shorebird-example'),
          App(appId: 'shorebird-counter'),
        ];

        when(
          () => httpClient.get(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(json.encode(expected), HttpStatus.ok),
        );

        final actual = await codePushClient.getApps();
        expect(json.encode(actual), equals(json.encode(expected)));
      });
    });

    group('close', () {
      test('closes the underlying client', () {
        codePushClient.close();
        verify(() => httpClient.close()).called(1);
      });
    });
  });
}

extension on ErrorResponse {
  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      'details': details,
    };
  }
}

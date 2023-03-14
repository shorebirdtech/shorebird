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
    const productId = 'shorebird-example';

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
          codePushClient.createApp(productId: productId),
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

        await codePushClient.createApp(productId: productId);

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
      test('throws an exception if the http request fails', () async {
        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.empty(),
            400,
          );
        });

        expect(
          codePushClient.createPatch(
            artifactPath: fixture.path,
            baseVersion: '1.0.0',
            productId: 'shorebird-example',
            channel: 'stable',
          ),
          throwsA(isA<Exception>()),
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
          baseVersion: '1.0.0',
          productId: 'shorebird-example',
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
      test('throws an exception if the http request fails', () async {
        when(
          () => httpClient.delete(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) async => http.Response('', HttpStatus.badRequest));

        expect(
          codePushClient.deleteApp(productId: productId),
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

        await codePushClient.deleteApp(productId: productId);

        final uri = verify(
          () => httpClient.delete(
            captureAny(),
            headers: any(named: 'headers'),
          ),
        ).captured.single as Uri;

        expect(
          uri,
          codePushClient.hostedUri.replace(
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
          Uri.parse(
            'https://storage.googleapis.com/code-push-dev.appspot.com/engines/dev/engine.zip',
          ),
        );
      });
    });

    group('getApps', () {
      test('throws an exception if the http request fails', () async {
        when(
          () => httpClient.get(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) async => http.Response('', HttpStatus.badRequest));

        expect(
          codePushClient.getApps(),
          throwsA(isA<Exception>()),
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
          App(
            productId: 'shorebird-example',
            releases: [
              Release(
                version: '1.0.0',
                patches: [
                  Patch(
                    number: 1,
                    channels: ['stable'],
                    artifacts: [
                      Artifact(
                        arch: 'aarm64',
                        platform: 'android',
                        url: 'http://localhost:8080',
                        hash: '#',
                      )
                    ],
                  ),
                  Patch(
                    number: 2,
                    channels: ['stable', 'dev'],
                    artifacts: [
                      Artifact(
                        arch: 'aarm64',
                        platform: 'android',
                        url: 'http://localhost:8080',
                        hash: '#',
                      )
                    ],
                  )
                ],
              ),
              Release(version: '2.0.0'),
            ],
          ),
          App(
            productId: 'shorebird-counter',
            releases: [
              Release(
                version: '1.0.0',
                patches: [
                  Patch(
                    number: 1,
                    channels: ['stable'],
                    artifacts: [
                      Artifact(
                        arch: 'aarm64',
                        platform: 'android',
                        url: 'http://localhost:8080',
                        hash: '#',
                      )
                    ],
                  ),
                  Patch(
                    number: 2,
                    channels: ['stable', 'dev'],
                    artifacts: [
                      Artifact(
                        arch: 'aarm64',
                        platform: 'android',
                        url: 'http://localhost:8080',
                        hash: '#',
                      )
                    ],
                  )
                ],
              ),
              Release(
                version: '1.0.1',
                patches: [
                  Patch(
                    number: 1,
                    channels: ['stable'],
                    artifacts: [
                      Artifact(
                        arch: 'aarm64',
                        platform: 'android',
                        url: 'http://localhost:8080',
                        hash: '#',
                      )
                    ],
                  ),
                ],
              ),
            ],
          ),
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

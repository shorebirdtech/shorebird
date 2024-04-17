// ignore_for_file: prefer_const_constructors
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

void main() {
  group(CodePushClient, () {
    const appId = 'app-id';
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const displayName = 'shorebird-example';
    const errorResponse = ErrorResponse(
      code: 'test_code',
      message: 'test message',
      details: 'test details',
    );
    const customHeaders = {'x-custom-header': 'custom-value'};
    final expectedHeaders = {
      ...CodePushClient.standardHeaders,
      ...customHeaders,
    };

    late http.Client httpClient;
    late CodePushClient codePushClient;

    Uri v1(String endpoint) {
      return Uri.parse('${codePushClient.hostedUri}/api/v1/$endpoint');
    }

    setUpAll(() {
      registerFallbackValue(_FakeBaseRequest());
      registerFallbackValue(Uri());
    });

    setUp(() {
      httpClient = _MockHttpClient();
      codePushClient = CodePushClient(
        httpClient: httpClient,
        customHeaders: customHeaders,
      );
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(Stream.empty(), HttpStatus.ok),
      );
    });

    test('can be instantiated', () {
      expect(CodePushClient(), isNotNull);
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

    test('throws CodePushUpgradeRequiredException on 426 response', () async {
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.empty(),
          HttpStatus.upgradeRequired,
        ),
      );

      expect(
        codePushClient.getApps(),
        throwsA(isA<CodePushUpgradeRequiredException>()),
      );
    });

    test('throws CodePushForbiddenException on 403 response', () async {
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.empty(),
          HttpStatus.forbidden,
        ),
      );

      expect(
        codePushClient.getApps(),
        throwsA(isA<CodePushForbiddenException>()),
      );
    });

    group('getCurrentUser', () {
      const user = User(
        id: 123,
        email: 'tester@shorebird.dev',
        jwtIssuer: 'https://accounts.google.com',
      );

      test('makes the correct request', () async {
        codePushClient.getCurrentUser().ignore();
        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;
        expect(request.method, equals('GET'));
        expect(request.url, equals(v1('users/me')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('returns null if reponse is a 404', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.notFound,
          ),
        );
        expect(await codePushClient.getCurrentUser(), isNull);
      });

      test('throws exception if the http request fails', () {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.badRequest,
          ),
        );

        expect(
          codePushClient.getCurrentUser(),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessage,
            ),
          ),
        );
      });

      test('returns a deserialize user if the request succeeds', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(user.toJson()))),
            HttpStatus.ok,
          ),
        );

        final responseUser = await codePushClient.getCurrentUser();
        expect(responseUser, isNotNull);
        expect(responseUser!.id, user.id);
        expect(responseUser.email, user.email);
        expect(responseUser.hasActiveSubscription, user.hasActiveSubscription);
      });
    });

    group('createPatchArtifact', () {
      const patchId = 0;
      const arch = 'aarch64';
      const platform = ReleasePlatform.android;
      const hash = 'test-hash';
      const size = 42;

      test('makes the correct request', () async {
        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        try {
          await codePushClient.createPatchArtifact(
            appId: appId,
            artifactPath: fixture.path,
            patchId: patchId,
            arch: arch,
            platform: platform,
            hash: hash,
          );
        } catch (_) {}

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;
        expect(request.method, equals('POST'));
        expect(
          request.url,
          equals(v1('apps/$appId/patches/$patchId/artifacts')),
        );
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the http request fails (unknown)', () async {
        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.failedDependency,
          );
        });

        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        expect(
          codePushClient.createPatchArtifact(
            appId: appId,
            artifactPath: fixture.path,
            patchId: patchId,
            arch: arch,
            platform: platform,
            hash: hash,
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
        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          );
        });

        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        expect(
          codePushClient.createPatchArtifact(
            appId: appId,
            artifactPath: fixture.path,
            patchId: patchId,
            arch: arch,
            platform: platform,
            hash: hash,
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

      test('throws an exception if the upload fails', () async {
        const artifactId = 42;
        const uploadUrl = 'https://example.com';
        final responses = [
          http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(
                  CreatePatchArtifactResponse(
                    id: artifactId,
                    patchId: patchId,
                    arch: arch,
                    platform: platform,
                    hash: hash,
                    size: size,
                    url: uploadUrl,
                  ),
                ),
              ),
            ),
            HttpStatus.ok,
          ),
          http.StreamedResponse(Stream.empty(), HttpStatus.badRequest),
        ];
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => responses.removeAt(0),
        );

        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        await expectLater(
          codePushClient.createPatchArtifact(
            appId: appId,
            artifactPath: fixture.path,
            patchId: patchId,
            arch: arch,
            platform: platform,
            hash: hash,
          ),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              contains('Failed to upload artifact'),
            ),
          ),
        );
        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .last as http.BaseRequest;
        expect(request.url, equals(Uri.parse(uploadUrl)));
        expect(
          (request as http.MultipartRequest).files.single.length,
          equals(fixture.readAsBytesSync().lengthInBytes),
        );
      });

      test('completes when request succeeds', () async {
        const artifactId = 42;
        const uploadUrl = 'https://example.com';
        final responses = [
          http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(
                  CreatePatchArtifactResponse(
                    id: artifactId,
                    patchId: patchId,
                    arch: arch,
                    platform: platform,
                    hash: hash,
                    size: size,
                    url: uploadUrl,
                  ),
                ),
              ),
            ),
            HttpStatus.ok,
          ),
          http.StreamedResponse(Stream.empty(), HttpStatus.noContent),
        ];
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => responses.removeAt(0),
        );

        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        await expectLater(
          codePushClient.createPatchArtifact(
            appId: appId,
            artifactPath: fixture.path,
            patchId: patchId,
            arch: arch,
            platform: platform,
            hash: hash,
          ),
          completes,
        );

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .first as http.MultipartRequest;

        expect(
          request.url,
          codePushClient.hostedUri.replace(
            path: '/api/v1/apps/$appId/patches/$patchId/artifacts',
          ),
        );
      });
    });

    group('createReleaseArtifact', () {
      const appId = 'test-app-id';
      const releaseId = 0;
      const arch = 'aarch64';
      const platform = ReleasePlatform.android;
      const hash = 'test-hash';
      const size = 5;
      const canSideload = true;

      test('makes the correct request', () async {
        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync()
          ..writeAsStringSync('hello');
        final expectedRequest = CreateReleaseArtifactRequest(
          arch: arch,
          platform: platform,
          hash: hash,
          size: size,
          canSideload: canSideload,
          filename: 'release.txt',
        );

        try {
          await codePushClient.createReleaseArtifact(
            appId: appId,
            artifactPath: fixture.path,
            releaseId: releaseId,
            arch: arch,
            platform: platform,
            hash: hash,
            canSideload: canSideload,
          );
        } catch (_) {}

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.MultipartRequest;
        expect(request.method, equals('POST'));
        expect(
          request.url,
          equals(v1('apps/$appId/releases/$releaseId/artifacts')),
        );
        expect(request.hasHeaders(expectedHeaders), isTrue);
        expect(
          MapEquality<String, dynamic>().equals(
            request.fields,
            expectedRequest.toJson(),
          ),
          isTrue,
        );
      });

      test('throws an exception if the http request fails (unknown)', () async {
        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.empty(),
            HttpStatus.failedDependency,
          );
        });

        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        expect(
          codePushClient.createReleaseArtifact(
            appId: appId,
            artifactPath: fixture.path,
            releaseId: releaseId,
            arch: arch,
            platform: platform,
            hash: hash,
            canSideload: canSideload,
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

      test(
          'throws a CodePushNotFoundException if the http response code is 404',
          () {
        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.notFound,
          );
        });

        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        expect(
          codePushClient.createReleaseArtifact(
            appId: appId,
            artifactPath: fixture.path,
            releaseId: releaseId,
            arch: arch,
            platform: platform,
            hash: hash,
            canSideload: canSideload,
          ),
          throwsA(isA<CodePushNotFoundException>()),
        );
      });

      test(
          'throws a CodePushConflictException if the http response code is 409',
          () {
        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.conflict,
          );
        });

        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        expect(
          codePushClient.createReleaseArtifact(
            appId: appId,
            artifactPath: fixture.path,
            releaseId: releaseId,
            arch: arch,
            platform: platform,
            hash: hash,
            canSideload: canSideload,
          ),
          throwsA(isA<CodePushConflictException>()),
        );
      });

      test('throws an exception if the http request fails', () async {
        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          );
        });

        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        expect(
          codePushClient.createReleaseArtifact(
            appId: appId,
            artifactPath: fixture.path,
            releaseId: releaseId,
            arch: arch,
            platform: platform,
            hash: hash,
            canSideload: canSideload,
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

      test('throws an exception if the upload fails', () async {
        const artifactId = 42;
        const uploadUrl = 'https://example.com';
        final responses = [
          http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(
                  CreateReleaseArtifactResponse(
                    id: artifactId,
                    releaseId: releaseId,
                    arch: arch,
                    platform: platform,
                    hash: hash,
                    size: size,
                    url: uploadUrl,
                  ),
                ),
              ),
            ),
            HttpStatus.ok,
          ),
          http.StreamedResponse(Stream.empty(), HttpStatus.badRequest),
        ];
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => responses.removeAt(0),
        );

        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        await expectLater(
          codePushClient.createReleaseArtifact(
            appId: appId,
            artifactPath: fixture.path,
            releaseId: releaseId,
            arch: arch,
            platform: platform,
            hash: hash,
            canSideload: canSideload,
          ),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              contains('Failed to upload artifact'),
            ),
          ),
        );
        final request = verify(
          () => httpClient.send(captureAny()),
        ).captured.last as http.BaseRequest;
        expect(request.url, equals(Uri.parse(uploadUrl)));
        expect(
          (request as http.MultipartRequest).files.single.length,
          equals(fixture.readAsBytesSync().lengthInBytes),
        );
      });

      test('completes when request succeeds', () async {
        const artifactId = 42;
        const uploadUrl = 'https://example.com';
        final responses = [
          http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(
                  CreateReleaseArtifactResponse(
                    id: artifactId,
                    releaseId: releaseId,
                    arch: arch,
                    platform: platform,
                    hash: hash,
                    size: size,
                    url: uploadUrl,
                  ),
                ),
              ),
            ),
            HttpStatus.ok,
          ),
          http.StreamedResponse(Stream.empty(), HttpStatus.noContent),
        ];
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => responses.removeAt(0),
        );

        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        await expectLater(
          codePushClient.createReleaseArtifact(
            appId: appId,
            artifactPath: fixture.path,
            releaseId: releaseId,
            arch: arch,
            platform: platform,
            hash: hash,
            canSideload: canSideload,
          ),
          completes,
        );

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .first as http.MultipartRequest;

        expect(
          request.url,
          codePushClient.hostedUri.replace(
            path: '/api/v1/apps/$appId/releases/$releaseId/artifacts',
          ),
        );
      });
    });

    group('createApp', () {
      test('makes the correct request', () async {
        codePushClient.createApp(displayName: displayName).ignore();
        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;
        expect(request.method, equals('POST'));
        expect(request.url, equals(v1('apps')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the http request fails (unknown)', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.badRequest,
          ),
        );

        expect(
          codePushClient.createApp(displayName: displayName),
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.createApp(displayName: displayName),
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(App(id: appId, displayName: displayName)),
              ),
            ),
            HttpStatus.ok,
          ),
        );

        await expectLater(
          codePushClient.createApp(displayName: displayName),
          completion(
            equals(
              isA<App>()
                  .having((a) => a.id, 'id', appId)
                  .having((a) => a.displayName, 'displayName', displayName),
            ),
          ),
        );

        final request = verify(
          () => httpClient.send(captureAny()),
        ).captured.single as http.BaseRequest;

        expect(
          request.url,
          codePushClient.hostedUri.replace(path: '/api/v1/apps'),
        );
      });
    });

    group('createChannel', () {
      const channel = 'stable';

      test('makes the correct request', () async {
        codePushClient.createChannel(appId: appId, channel: channel).ignore();
        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;
        expect(request.method, equals('POST'));
        expect(request.url, equals(v1('apps/$appId/channels')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the http request fails (unknown)', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.badRequest,
          ),
        );

        expect(
          codePushClient.createChannel(appId: appId, channel: channel),
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.createChannel(appId: appId, channel: channel),
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
        const channelId = 0;
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(
                  Channel(id: channelId, appId: appId, name: channel),
                ),
              ),
            ),
            HttpStatus.ok,
          ),
        );

        await expectLater(
          codePushClient.createChannel(appId: appId, channel: channel),
          completion(
            equals(
              isA<Channel>()
                  .having((c) => c.id, 'id', channelId)
                  .having((c) => c.appId, 'appId', appId)
                  .having((c) => c.name, 'name', channel),
            ),
          ),
        );

        final request = verify(
          () => httpClient.send(captureAny()),
        ).captured.single as http.BaseRequest;

        expect(
          request.url,
          codePushClient.hostedUri.replace(
            path: '/api/v1/apps/$appId/channels',
          ),
        );
      });
    });

    group('createPatch', () {
      const releaseId = 0;

      test('makes the correct request', () async {
        codePushClient
            .createPatch(
              appId: appId,
              releaseId: releaseId,
              metadata: CreatePatchMetadata.forTest(),
            )
            .ignore();
        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;
        expect(request.method, equals('POST'));
        expect(request.url, equals(v1('apps/$appId/patches')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the http request fails (unknown)', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.badRequest,
          ),
        );

        expect(
          codePushClient.createPatch(
            appId: appId,
            releaseId: releaseId,
            metadata: CreatePatchMetadata.forTest(),
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.createPatch(
            appId: appId,
            releaseId: releaseId,
            metadata: CreatePatchMetadata.forTest(),
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

      test('completes when request succeeds', () async {
        const patchId = 0;
        const patchNumber = 1;
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(Patch(id: patchId, number: patchNumber)),
              ),
            ),
            HttpStatus.ok,
          ),
        );

        await expectLater(
          codePushClient.createPatch(
            appId: appId,
            releaseId: releaseId,
            metadata: CreatePatchMetadata.forTest(),
          ),
          completion(
            equals(
              isA<Patch>()
                  .having((c) => c.id, 'id', patchId)
                  .having((c) => c.number, 'number', patchNumber),
            ),
          ),
        );

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;

        expect(
          request.url,
          codePushClient.hostedUri.replace(path: '/api/v1/apps/$appId/patches'),
        );
      });
    });

    group('createRelease', () {
      const version = '1.0.0';

      test('makes the correct request', () async {
        codePushClient
            .createRelease(
              appId: appId,
              version: version,
              flutterRevision: flutterRevision,
              displayName: displayName,
            )
            .ignore();
        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;
        expect(request.method, equals('POST'));
        expect(request.url, equals(v1('apps/$appId/releases')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the http request fails (unknown)', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.badRequest,
          ),
        );

        expect(
          codePushClient.createRelease(
            appId: appId,
            version: version,
            flutterRevision: flutterRevision,
            displayName: displayName,
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.createRelease(
            appId: appId,
            version: version,
            flutterRevision: flutterRevision,
            displayName: displayName,
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

      test('completes when request succeeds', () async {
        const releaseId = 0;
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(
                  CreateReleaseResponse(
                    release: Release(
                      id: releaseId,
                      appId: appId,
                      version: version,
                      flutterRevision: flutterRevision,
                      displayName: displayName,
                      platformStatuses: {},
                      createdAt: DateTime(2023),
                      updatedAt: DateTime(2023),
                    ),
                  ),
                ),
              ),
            ),
            HttpStatus.ok,
          ),
        );

        await expectLater(
          codePushClient.createRelease(
            appId: appId,
            version: version,
            flutterRevision: flutterRevision,
            displayName: displayName,
          ),
          completion(
            equals(
              isA<Release>()
                  .having((r) => r.id, 'id', releaseId)
                  .having((r) => r.appId, 'appId', appId)
                  .having((r) => r.version, 'version', version)
                  .having(
                    (r) => r.flutterRevision,
                    'flutterRevision',
                    flutterRevision,
                  )
                  .having((r) => r.displayName, 'displayName', displayName)
                  .having(
                (r) => r.platformStatuses,
                'platformStatuses',
                <ReleasePlatform, ReleaseStatus>{},
              ),
            ),
          ),
        );

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;

        expect(
          request.url,
          codePushClient.hostedUri
              .replace(path: '/api/v1/apps/$appId/releases'),
        );
      });
    });

    group('updateReleaseStatus', () {
      const appId = 'test-app-id';
      const releaseId = 42;
      const platform = ReleasePlatform.android;

      test('makes the correct request', () async {
        codePushClient
            .updateReleaseStatus(
              appId: appId,
              releaseId: releaseId,
              platform: platform,
              status: ReleaseStatus.active,
            )
            .ignore();
        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;
        expect(request.method, equals('PATCH'));
        expect(request.url, equals(v1('apps/$appId/releases/$releaseId')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the response is not a 204', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.badRequest,
          ),
        );

        expect(
          codePushClient.updateReleaseStatus(
            appId: appId,
            releaseId: releaseId,
            platform: platform,
            status: ReleaseStatus.active,
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

      test('completes when the server responds with a 204', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.noContent,
          ),
        );

        expect(
          codePushClient.updateReleaseStatus(
            appId: appId,
            releaseId: releaseId,
            platform: platform,
            status: ReleaseStatus.active,
          ),
          completes,
        );
      });
    });

    group('createUser', () {
      const userName = 'Jane Doe';
      final user = User(
        id: 1,
        email: 'tester@shorebird.dev',
        displayName: userName,
        jwtIssuer:
            'https://login.microsoftonline.com/9188040d-6c67-4c5b-b112-36a304b66dad/v2.0',
      );

      test('makes the correct request', () async {
        codePushClient.createUser(name: userName).ignore();
        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;
        expect(request.method, equals('POST'));
        expect(request.url, equals(v1('users')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the http request fails', () {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.createUser(name: userName),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessage,
            ),
          ),
        );
      });

      test('returns a User when the http request succeeds', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(user.toJson()))),
            HttpStatus.created,
          ),
        );

        final result = await codePushClient.createUser(name: userName);

        expect(result.toJson(), user.toJson());
      });
    });

    group('deleteApp', () {
      test('makes the correct request', () async {
        codePushClient.deleteApp(appId: appId).ignore();
        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;
        expect(request.method, equals('DELETE'));
        expect(request.url, equals(v1('apps/$appId')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the http request fails (unknown)', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.failedDependency,
          ),
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.noContent,
          ),
        );

        await codePushClient.deleteApp(appId: appId);

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;

        expect(
          request.url,
          codePushClient.hostedUri.replace(
            path: '/api/v1/apps/$appId',
          ),
        );
      });
    });

    group('getApps', () {
      test('makes the correct request', () async {
        codePushClient.getApps().ignore();
        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;
        expect(request.method, equals('GET'));
        expect(request.url, equals(v1('apps')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the http request fails (unknown)', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.badRequest,
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
        final expected = <AppMetadata>[];
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(json.encode(GetAppsResponse(apps: expected))),
            ),
            HttpStatus.ok,
          ),
        );

        final apps = await codePushClient.getApps();
        expect(apps, isEmpty);
      });

      test('completes when request succeeds (populated)', () async {
        final expected = [
          AppMetadata(
            appId: '1',
            displayName: 'Shorebird Example',
            createdAt: DateTime(2022),
            updatedAt: DateTime(2023),
          ),
          AppMetadata(
            appId: '2',
            displayName: 'Shorebird Clock',
            createdAt: DateTime(2022),
            updatedAt: DateTime(2023),
          ),
        ];

        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(json.encode(GetAppsResponse(apps: expected))),
            ),
            HttpStatus.ok,
          ),
        );

        final actual = await codePushClient.getApps();
        expect(json.encode(actual), equals(json.encode(expected)));
      });
    });

    group('getChannels', () {
      const appId = 'test-app-id';

      test('makes the correct request', () async {
        codePushClient.getChannels(appId: appId).ignore();
        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;
        expect(request.method, equals('GET'));
        expect(request.url, equals(v1('apps/$appId/channels')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the http request fails (unknown)', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.getChannels(appId: appId),
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.getChannels(appId: appId),
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode([]))),
            HttpStatus.ok,
          ),
        );

        final apps = await codePushClient.getChannels(appId: appId);
        expect(apps, isEmpty);
      });

      test('completes when request succeeds (populated)', () async {
        final expected = [
          Channel(id: 0, appId: '1', name: 'stable'),
          Channel(id: 1, appId: '2', name: 'development'),
        ];

        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(expected))),
            HttpStatus.ok,
          ),
        );

        final actual = await codePushClient.getChannels(appId: appId);
        expect(json.encode(actual), equals(json.encode(expected)));
      });
    });

    group('getReleases', () {
      const appId = 'test-app-id';

      group('makes the correct request', () {
        test('when sideloadableOnly is not specified', () async {
          codePushClient.getReleases(appId: appId).ignore();
          final request = verify(() => httpClient.send(captureAny()))
              .captured
              .single as http.BaseRequest;
          expect(request.method, equals('GET'));
          expect(request.url, equals(v1('apps/$appId/releases')));
          expect(request.hasHeaders(expectedHeaders), isTrue);
        });

        test('when sideloadableOnly is true', () async {
          codePushClient
              .getReleases(appId: appId, sideloadableOnly: true)
              .ignore();
          final request = verify(() => httpClient.send(captureAny()))
              .captured
              .single as http.BaseRequest;
          expect(request.method, equals('GET'));
          expect(
            request.url,
            equals(v1('apps/$appId/releases?sideloadable=true')),
          );
          expect(request.hasHeaders(expectedHeaders), isTrue);
        });
      });

      test('throws an exception if the http request fails (unknown)', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.getReleases(appId: appId),
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.getReleases(appId: appId),
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(json.encode(GetReleasesResponse(releases: []))),
            ),
            HttpStatus.ok,
          ),
        );

        final releases = await codePushClient.getReleases(appId: appId);
        expect(releases, isEmpty);
      });

      test('completes when request succeeds (populated)', () async {
        final expected = [
          Release(
            id: 0,
            appId: '1',
            version: '1.0.0',
            flutterRevision: flutterRevision,
            displayName: 'v1.0.0',
            platformStatuses: {ReleasePlatform.android: ReleaseStatus.draft},
            createdAt: DateTime(2022),
            updatedAt: DateTime(2023),
          ),
          Release(
            id: 1,
            appId: '2',
            version: '1.0.1',
            flutterRevision: flutterRevision,
            displayName: 'v1.0.1',
            platformStatuses: {},
            createdAt: DateTime(2022),
            updatedAt: DateTime(2023),
          ),
        ];

        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(json.encode(GetReleasesResponse(releases: expected))),
            ),
            HttpStatus.ok,
          ),
        );

        final actual = await codePushClient.getReleases(appId: appId);
        expect(json.encode(actual), equals(json.encode(expected)));
      });
    });

    group('getReleaseArtifacts', () {
      const appId = 'test-app-id';
      const releaseId = 0;
      const arch = 'aarch64';
      const platform = ReleasePlatform.android;

      test('makes the correct request', () async {
        codePushClient
            .getReleaseArtifacts(
              appId: appId,
              releaseId: releaseId,
              arch: arch,
              platform: platform,
            )
            .ignore();
        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;
        expect(request.method, equals('GET'));
        expect(
          request.url,
          equals(
            v1('apps/$appId/releases/$releaseId/artifacts?arch=$arch&platform=${platform.name}'),
          ),
        );
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the http request fails (unknown)', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.getReleaseArtifacts(
            appId: appId,
            releaseId: releaseId,
            arch: arch,
            platform: platform,
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.getReleaseArtifacts(
            appId: appId,
            releaseId: releaseId,
            arch: arch,
            platform: platform,
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

      test('completes when request succeeds', () async {
        final expected = [
          ReleaseArtifact(
            id: 0,
            releaseId: releaseId,
            arch: arch,
            platform: platform,
            url: 'https://example.com',
            hash: '#',
            size: 42,
          ),
        ];

        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(GetReleaseArtifactsResponse(artifacts: expected)),
              ),
            ),
            HttpStatus.ok,
          ),
        );

        final actual = await codePushClient.getReleaseArtifacts(
          appId: appId,
          releaseId: releaseId,
          arch: arch,
          platform: platform,
        );
        expect(json.encode(actual), equals(json.encode(expected)));
      });
    });

    group('promotePatch', () {
      const patchId = 0;
      const channelId = 0;

      test('makes the correct request', () async {
        codePushClient
            .promotePatch(appId: appId, patchId: patchId, channelId: channelId)
            .ignore();
        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;
        expect(request.method, equals('POST'));
        expect(request.url, equals(v1('apps/$appId/patches/promote')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the http request fails (unknown)', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.badRequest,
          ),
        );

        expect(
          codePushClient.promotePatch(
            appId: appId,
            patchId: patchId,
            channelId: channelId,
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.promotePatch(
            appId: appId,
            patchId: patchId,
            channelId: channelId,
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

      test('completes when request succeeds', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.created,
          ),
        );

        await expectLater(
          codePushClient.promotePatch(
            appId: appId,
            patchId: patchId,
            channelId: channelId,
          ),
          completes,
        );

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.BaseRequest;

        expect(
          request.url,
          codePushClient.hostedUri
              .replace(path: '/api/v1/apps/$appId/patches/promote'),
        );
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

extension on http.BaseRequest {
  bool hasHeaders(Map<String, String> expectedHeaders) {
    return headers.entries.every(
      (entry) => headers[entry.key] == entry.value,
    );
  }
}

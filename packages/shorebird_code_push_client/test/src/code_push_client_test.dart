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
    const appId = 'app-id';
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const displayName = 'shorebird-example';
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
      codePushClient = CodePushClient(httpClient: httpClient);
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

    group('createAppCollaborator', () {
      const appId = 'test-app-id';
      const userId = 42;

      test('throws an exception if the http request fails (unknown)', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response('', HttpStatus.failedDependency),
        );

        expect(
          codePushClient.createAppCollaborator(appId: appId, userId: userId),
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
          codePushClient.createAppCollaborator(appId: appId, userId: userId),
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

        await codePushClient.createAppCollaborator(
          appId: appId,
          userId: userId,
        );

        final uri = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).captured.single as Uri;

        expect(
          uri,
          codePushClient.hostedUri.replace(
            path: '/api/v1/apps/$appId/collaborators',
          ),
        );
      });
    });

    group('getCurrentUser', () {
      const user = User(id: 123, email: 'tester@shorebird.dev');

      late Uri uri;
      setUp(() {
        uri = Uri.parse('${codePushClient.hostedUri}/api/v1/users/me');
      });

      test('returns null if reponse is a 404', () async {
        when(() => httpClient.get(uri))
            .thenAnswer((_) async => http.Response('', HttpStatus.notFound));
        expect(await codePushClient.getCurrentUser(), isNull);
      });

      test('throws exception if the http request fails', () {
        when(() => httpClient.get(uri))
            .thenAnswer((_) async => http.Response('', HttpStatus.badRequest));

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
        when(() => httpClient.get(uri)).thenAnswer(
          (_) async => http.Response(jsonEncode(user.toJson()), HttpStatus.ok),
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
      const platform = 'android';
      const hash = 'test-hash';
      const size = 42;

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
          codePushClient.createPatchArtifact(
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

      test('completes when request succeeds', () async {
        const artifactId = 0;
        const artifactUrl = 'https://example.com/artifact.zip';
        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(
                  PatchArtifact(
                    id: artifactId,
                    url: artifactUrl,
                    patchId: patchId,
                    arch: arch,
                    platform: platform,
                    hash: hash,
                    size: size,
                  ),
                ),
              ),
            ),
            HttpStatus.ok,
          );
        });

        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        await expectLater(
          codePushClient.createPatchArtifact(
            artifactPath: fixture.path,
            patchId: patchId,
            arch: arch,
            platform: platform,
            hash: hash,
          ),
          completion(
            equals(
              isA<PatchArtifact>()
                  .having((a) => a.id, 'id', artifactId)
                  .having((a) => a.patchId, 'patchId', patchId)
                  .having((a) => a.arch, 'arch', arch)
                  .having((a) => a.platform, 'platform', platform)
                  .having((a) => a.hash, 'hash', hash)
                  .having((a) => a.url, 'artifactUrl', artifactUrl),
            ),
          ),
        );

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.MultipartRequest;

        expect(
          request.url,
          codePushClient.hostedUri.replace(
            path: '/api/v1/patches/$patchId/artifacts',
          ),
        );
      });
    });

    group('createPaymentLink', () {
      test('throws an exception if the http request fails', () {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) async => http.Response('', HttpStatus.badRequest));

        expect(
          codePushClient.createPaymentLink(),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessage,
            ),
          ),
        );
      });

      test('returns a payment link if the http request succeeds', () {
        final link = Uri.parse('http://test.com');

        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode(CreatePaymentLinkResponse(paymentLink: link).toJson()),
            HttpStatus.ok,
          ),
        );

        expect(
          codePushClient.createPaymentLink(),
          completion(link),
        );
      });
    });

    group('createReleaseArtifact', () {
      const releaseId = 0;
      const arch = 'aarch64';
      const platform = 'android';
      const hash = 'test-hash';
      const size = 42;

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
            artifactPath: fixture.path,
            releaseId: releaseId,
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
          codePushClient.createReleaseArtifact(
            artifactPath: fixture.path,
            releaseId: releaseId,
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

      test('completes when request succeeds', () async {
        const artifactId = 0;
        const artifactUrl = 'https://example.com/artifact.zip';
        when(() => httpClient.send(any())).thenAnswer((_) async {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(
                  ReleaseArtifact(
                    id: artifactId,
                    url: artifactUrl,
                    releaseId: releaseId,
                    arch: arch,
                    platform: platform,
                    hash: hash,
                    size: size,
                  ),
                ),
              ),
            ),
            HttpStatus.ok,
          );
        });

        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..createSync();

        await expectLater(
          codePushClient.createReleaseArtifact(
            artifactPath: fixture.path,
            releaseId: releaseId,
            arch: arch,
            platform: platform,
            hash: hash,
          ),
          completion(
            equals(
              isA<ReleaseArtifact>()
                  .having((a) => a.id, 'id', artifactId)
                  .having((a) => a.releaseId, 'releaseId', releaseId)
                  .having((a) => a.arch, 'arch', arch)
                  .having((a) => a.platform, 'platform', platform)
                  .having((a) => a.hash, 'hash', hash)
                  .having((a) => a.url, 'artifactUrl', artifactUrl),
            ),
          ),
        );

        final request = verify(() => httpClient.send(captureAny()))
            .captured
            .single as http.MultipartRequest;

        expect(
          request.url,
          codePushClient.hostedUri.replace(
            path: '/api/v1/releases/$releaseId/artifacts',
          ),
        );
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
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            json.encode(App(id: appId, displayName: displayName)),
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

    group('createChannel', () {
      const channel = 'stable';
      test('throws an exception if the http request fails (unknown)', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('', HttpStatus.badRequest));

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
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            json.encode(Channel(id: channelId, appId: appId, name: channel)),
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

        final uri = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).captured.single as Uri;

        expect(
          uri,
          codePushClient.hostedUri.replace(path: '/api/v1/channels'),
        );
      });
    });

    group('createPatch', () {
      const releaseId = 0;
      test('throws an exception if the http request fails (unknown)', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('', HttpStatus.badRequest));

        expect(
          codePushClient.createPatch(releaseId: releaseId),
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
          codePushClient.createPatch(releaseId: releaseId),
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
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            json.encode(Patch(id: patchId, number: patchNumber)),
            HttpStatus.ok,
          ),
        );

        await expectLater(
          codePushClient.createPatch(releaseId: releaseId),
          completion(
            equals(
              isA<Patch>()
                  .having((c) => c.id, 'id', patchId)
                  .having((c) => c.number, 'number', patchNumber),
            ),
          ),
        );

        final uri = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).captured.single as Uri;

        expect(
          uri,
          codePushClient.hostedUri.replace(path: '/api/v1/patches'),
        );
      });
    });

    group('createRelease', () {
      const version = '1.0.0';
      test('throws an exception if the http request fails (unknown)', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('', HttpStatus.badRequest));

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
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            json.encode(
              Release(
                id: releaseId,
                appId: appId,
                version: version,
                flutterRevision: flutterRevision,
                displayName: displayName,
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
                  .having((r) => r.displayName, 'displayName', displayName),
            ),
          ),
        );

        final uri = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).captured.single as Uri;

        expect(
          uri,
          codePushClient.hostedUri.replace(path: '/api/v1/releases'),
        );
      });
    });

    group('deleteRelease', () {
      const releaseId = 42;

      test('throws an exception if the http request fails (unknown)', () async {
        when(
          () => httpClient.delete(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response('', HttpStatus.failedDependency),
        );

        expect(
          codePushClient.deleteRelease(releaseId: releaseId),
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
          codePushClient.deleteRelease(releaseId: releaseId),
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

        await codePushClient.deleteRelease(releaseId: releaseId);

        final uri = verify(
          () => httpClient.delete(
            captureAny(),
            headers: any(named: 'headers'),
          ),
        ).captured.single as Uri;

        expect(
          uri,
          codePushClient.hostedUri.replace(
            path: '/api/v1/releases/$releaseId',
          ),
        );
      });
    });

    group('createUser', () {
      const userName = 'Jane Doe';
      final user = User(
        id: 1,
        email: 'tester@shorebird.dev',
        displayName: userName,
      );

      test('throws an exception if the http request fails', () {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response('', HttpStatus.failedDependency),
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
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode(user.toJson()),
            HttpStatus.created,
          ),
        );

        final result = await codePushClient.createUser(name: userName);

        expect(result.toJson(), user.toJson());
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
          AppMetadata(appId: '1', displayName: 'Shorebird Example'),
          AppMetadata(appId: '2', displayName: 'Shorebird Clock'),
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

    group('getChannels', () {
      const appId = 'test-app-id';
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
        when(
          () => httpClient.get(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(json.encode([]), HttpStatus.ok),
        );

        final apps = await codePushClient.getChannels(appId: appId);
        expect(apps, isEmpty);
      });

      test('completes when request succeeds (populated)', () async {
        final expected = [
          Channel(id: 0, appId: '1', name: 'stable'),
          Channel(id: 1, appId: '2', name: 'development'),
        ];

        when(
          () => httpClient.get(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(json.encode(expected), HttpStatus.ok),
        );

        final actual = await codePushClient.getChannels(appId: appId);
        expect(json.encode(actual), equals(json.encode(expected)));
      });
    });

    group('getReleases', () {
      const appId = 'test-app-id';
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
        when(
          () => httpClient.get(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(json.encode([]), HttpStatus.ok),
        );

        final apps = await codePushClient.getReleases(appId: appId);
        expect(apps, isEmpty);
      });

      test('completes when request succeeds (populated)', () async {
        final expected = [
          Release(
            id: 0,
            appId: '1',
            version: '1.0.0',
            flutterRevision: flutterRevision,
            displayName: 'v1.0.0',
          ),
          Release(
            id: 1,
            appId: '2',
            version: '1.0.1',
            flutterRevision: flutterRevision,
            displayName: 'v1.0.1',
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

        final actual = await codePushClient.getReleases(appId: appId);
        expect(json.encode(actual), equals(json.encode(expected)));
      });
    });

    group('getReleaseArtifact', () {
      const releaseId = 0;
      const arch = 'aarch64';
      const platform = 'android';

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
          codePushClient.getReleaseArtifact(
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
          codePushClient.getReleaseArtifact(
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
        final expected = ReleaseArtifact(
          id: 0,
          releaseId: releaseId,
          arch: arch,
          platform: platform,
          url: 'https://example.com',
          hash: '#',
          size: 42,
        );

        when(
          () => httpClient.get(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(json.encode(expected), HttpStatus.ok),
        );

        final actual = await codePushClient.getReleaseArtifact(
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
      test('throws an exception if the http request fails (unknown)', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('', HttpStatus.badRequest));

        expect(
          codePushClient.promotePatch(patchId: patchId, channelId: channelId),
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
          codePushClient.promotePatch(patchId: patchId, channelId: channelId),
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
        ).thenAnswer(
          (_) async => http.Response('', HttpStatus.created),
        );

        await expectLater(
          codePushClient.promotePatch(patchId: patchId, channelId: channelId),
          completes,
        );

        final uri = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).captured.single as Uri;

        expect(
          uri,
          codePushClient.hostedUri.replace(path: '/api/v1/patches/promote'),
        );
      });
    });

    group('cancelSubscription', () {
      late Uri uri;

      setUp(() {
        uri = Uri.parse('${codePushClient.hostedUri}/api/v1/subscriptions');
      });

      test('throws an exception if the http request fails', () {
        when(() => httpClient.delete(uri))
            .thenAnswer((_) async => http.Response('', HttpStatus.badRequest));

        expect(
          codePushClient.cancelSubscription(),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessage,
            ),
          ),
        );
      });

      test('completes when request succeeds', () async {
        const timestamp = 1681455600;

        when(() => httpClient.delete(uri)).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'expiration_date': 1681455600}),
            HttpStatus.ok,
          ),
        );

        final response = await codePushClient.cancelSubscription();

        expect(response.millisecondsSinceEpoch, timestamp * 1000);
        verify(() => httpClient.delete(uri)).called(1);
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

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
  group(CodePushClient, () {
    const appId = 'app-id';
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const flutterVersion = '3.22.0';
    const displayName = 'shorebird-example';
    const organizationId = 1234;
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
    const podfileLockHash = 'podfile-lock-hash';

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
        // Disable backoff delays so retry paths run instantly under test.
        uploadRetryBaseDelay: Duration.zero,
      );
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
      );
    });

    test('can be instantiated', () {
      expect(CodePushClient(), isNotNull);
    });

    test('apiBaseUri is the hosted uri followed by /api/v1', () {
      expect(
        codePushClient.apiBaseUri,
        equals(Uri.parse('https://api.shorebird.dev/api/v1')),
      );
    });

    group('send', () {
      test('sends the request with the standard and custom headers', () async {
        final request = http.Request('POST', v1('apps'))..body = '{}';
        final response = await codePushClient.send(request);
        expect(response.statusCode, equals(HttpStatus.ok));
        final sent =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
        expect(sent, same(request));
        expect(sent.hasHeaders(expectedHeaders), isTrue);
      });

      test('returns error responses without throwing', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.notFound),
        );
        final response = await codePushClient.send(
          http.Request('GET', v1('apps/missing')),
        );
        expect(response.statusCode, equals(HttpStatus.notFound));
      });
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

    test('exceptions carry the ErrorResponse code', () async {
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
          HttpStatus.failedDependency,
        ),
      );

      await expectLater(
        codePushClient.getApps(),
        throwsA(
          isA<CodePushException>()
              .having((e) => e.code, 'code', errorResponse.code)
              .having((e) => e.details, 'details', errorResponse.details)
              .having(
                (e) => e.statusCode,
                'statusCode',
                HttpStatus.failedDependency,
              )
              .having((e) => e.response, 'response', errorResponse),
        ),
      );
    });

    test('throws CodePushUpgradeRequiredException on 426 response', () async {
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          const Stream.empty(),
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
        (_) async =>
            http.StreamedResponse(const Stream.empty(), HttpStatus.forbidden),
      );

      expect(
        codePushClient.getApps(),
        throwsA(isA<CodePushForbiddenException>()),
      );
    });

    group('getCurrentUser', () {
      const user = PrivateUser(
        id: 123,
        email: 'tester@shorebird.dev',
        jwtIssuer: 'https://accounts.google.com',
      );

      test('makes the correct request', () async {
        codePushClient.getCurrentUser().ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
        expect(request.method, equals('GET'));
        expect(request.url, equals(v1('users/me')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('returns null if response is a 404', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.notFound),
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
              CodePushClient.unknownErrorMessageFor(HttpStatus.badRequest),
            ),
          ),
        );
      });

      group('when the error body is not JSON', () {
        test('surfaces the status code and the body as details', () {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(
                utf8.encode('<html><body>\n  502 Bad Gateway\n</body></html>'),
              ),
              HttpStatus.badGateway,
            ),
          );

          expect(
            codePushClient.getCurrentUser(),
            throwsA(
              isA<CodePushException>()
                  .having(
                    (e) => e.message,
                    'message',
                    CodePushClient.unknownErrorMessageFor(
                      HttpStatus.badGateway,
                    ),
                  )
                  .having(
                    (e) => e.details,
                    'details',
                    '<html><body> 502 Bad Gateway </body></html>',
                  )
                  .having(
                    (e) => e.statusCode,
                    'statusCode',
                    HttpStatus.badGateway,
                  )
                  .having((e) => e.response, 'response', isNull),
            ),
          );
        });

        test('truncates a long body', () {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(utf8.encode('x' * 500)),
              HttpStatus.badGateway,
            ),
          );

          expect(
            codePushClient.getCurrentUser(),
            throwsA(
              isA<CodePushException>().having(
                (e) => e.details,
                'details',
                '${'x' * 200}...',
              ),
            ),
          );
        });

        test('omits details when the body is empty', () {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(utf8.encode('   \n  ')),
              HttpStatus.badGateway,
            ),
          );

          expect(
            codePushClient.getCurrentUser(),
            throwsA(
              isA<CodePushException>().having(
                (e) => e.details,
                'details',
                isNull,
              ),
            ),
          );
        });
      });

      test('returns a deserialize user if the request succeeds', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(user.toJson()))),
            HttpStatus.ok,
          ),
        );

        final responseUser = await codePushClient.getCurrentUser();
        expect(responseUser, equals(user));
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
        } on Exception {
          // ignore
        }

        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.MultipartRequest;
        expect(request.method, equals('POST'));
        expect(
          request.url,
          equals(v1('apps/$appId/patches/$patchId/artifacts')),
        );
        expect(request.hasHeaders(expectedHeaders), isTrue);
        expect(
          request.fields,
          equals({
            'arch': arch,
            'platform': platform.name,
            'hash': hash,
            'size': '${fixture.readAsBytesSync().lengthInBytes}',
          }),
        );
      });

      group('when a hash signature is provided', () {
        const hashSignature = 'hash_signature';
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
              hashSignature: hashSignature,
            );
          } on Exception {
            // ignore
          }

          final request =
              verify(() => httpClient.send(captureAny())).captured.single
                  as http.MultipartRequest;
          expect(request.method, equals('POST'));
          expect(
            request.url,
            equals(v1('apps/$appId/patches/$patchId/artifacts')),
          );
          expect(request.hasHeaders(expectedHeaders), isTrue);
          expect(
            request.fields,
            equals({
              'arch': arch,
              'platform': platform.name,
              'hash': hash,
              'size': '${fixture.readAsBytesSync().lengthInBytes}',
              'hash_signature': hashSignature,
            }),
          );
        });
      });

      group('when a podfile lock hash is provided', () {
        const podfileLockHash = 'podfile-lock-hash';

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
              podfileLockHash: podfileLockHash,
            );
          } on Exception {
            // ignore
          }

          final request =
              verify(() => httpClient.send(captureAny())).captured.single
                  as http.MultipartRequest;
          expect(request.method, equals('POST'));
          expect(
            request.url,
            equals(v1('apps/$appId/patches/$patchId/artifacts')),
          );
          expect(request.hasHeaders(expectedHeaders), isTrue);
          expect(request.fields['podfile_lock_hash'], equals(podfileLockHash));
        });
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
              CodePushClient.unknownErrorMessageFor(
                HttpStatus.failedDependency,
              ),
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

      test('throws CodePushUploadException if the upload fails', () async {
        const artifactId = 42;
        const uploadUrl = 'https://example.com';
        final responses = [
          http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(
                  const CreatePatchArtifactResponse(
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
          // A storage 409 must not read as an API conflict.
          http.StreamedResponse(const Stream.empty(), HttpStatus.conflict),
        ];
        when(
          () => httpClient.send(any()),
        ).thenAnswer((_) async => responses.removeAt(0));

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
            isA<CodePushUploadException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains('Failed to upload artifact'),
                )
                .having((e) => e.statusCode, 'statusCode', HttpStatus.conflict)
                .having(
                  (e) => e,
                  'exception',
                  isNot(isA<CodePushConflictException>()),
                ),
          ),
        );
        final request =
            verify(() => httpClient.send(captureAny())).captured.last
                as http.BaseRequest;
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
                  const CreatePatchArtifactResponse(
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
          http.StreamedResponse(const Stream.empty(), HttpStatus.noContent),
        ];
        when(
          () => httpClient.send(any()),
        ).thenAnswer((_) async => responses.removeAt(0));

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

        final request =
            verify(() => httpClient.send(captureAny())).captured.first
                as http.MultipartRequest;

        expect(
          request.url,
          codePushClient.hostedUri.replace(
            path: '/api/v1/apps/$appId/patches/$patchId/artifacts',
          ),
        );
      });

      test('uploads via a resumable session when the server '
          'selects resumable', () async {
        const artifactId = 42;
        const sessionUrl = 'https://storage.googleapis.com/session?upload_id=a';
        final responses = [
          http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(
                  const CreatePatchArtifactResponse(
                    id: artifactId,
                    patchId: patchId,
                    arch: arch,
                    platform: platform,
                    hash: hash,
                    size: size,
                    url: sessionUrl,
                    uploadMethod: ArtifactUploadMethod.resumable,
                  ),
                ),
              ),
            ),
            HttpStatus.ok,
          ),
          http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
        ];
        when(
          () => httpClient.send(any()),
        ).thenAnswer((_) async => responses.removeAt(0));

        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'patch.txt'))
          ..writeAsBytesSync([1, 2, 3, 4, 5]);

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

        final requests = verify(
          () => httpClient.send(captureAny()),
        ).captured.cast<http.BaseRequest>();
        expect(requests, hasLength(2));
        final uploadRequest = requests.last;
        expect(uploadRequest.method, equals('PUT'));
        expect(uploadRequest.url, equals(Uri.parse(sessionUrl)));
        expect(uploadRequest.headers['content-range'], equals('bytes 0-4/5'));
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

      // Multipart form fields are always strings on the wire, so the
      // expected payloads are spelled out as Map<String, String>.
      // CreateReleaseArtifactRequest.toJson() returns JSON types (bool,
      // int, enum→string, etc.); the client stringifies at the multipart
      // boundary and drops null-valued keys (see createReleaseArtifact
      // in code_push_client.dart).
      group('when podfileLockHash is null', () {
        test('makes the correct request', () async {
          final tempDir = Directory.systemTemp.createTempSync();
          final fixture = File(path.join(tempDir.path, 'release.txt'))
            ..createSync()
            ..writeAsStringSync('hello');

          try {
            await codePushClient.createReleaseArtifact(
              appId: appId,
              artifactPath: fixture.path,
              releaseId: releaseId,
              arch: arch,
              platform: platform,
              hash: hash,
              canSideload: canSideload,
              podfileLockHash: null,
            );
          } on Exception {
            // ignore
          }

          final request =
              verify(() => httpClient.send(captureAny())).captured.single
                  as http.MultipartRequest;
          expect(request.method, equals('POST'));
          expect(
            request.url,
            equals(v1('apps/$appId/releases/$releaseId/artifacts')),
          );
          expect(request.hasHeaders(expectedHeaders), isTrue);
          expect(request.fields, <String, String>{
            'arch': arch,
            'platform': platform.name,
            'hash': hash,
            'filename': 'release.txt',
            'can_sideload': 'true',
            'size': '$size',
            // podfile_lock_hash absent.
          });
        });
      });

      group('when signing is provided', () {
        test('sends it as one JSON-encoded field', () async {
          final tempDir = Directory.systemTemp.createTempSync();
          final fixture = File(path.join(tempDir.path, 'release.txt'))
            ..createSync()
            ..writeAsStringSync('hello');

          try {
            await codePushClient.createReleaseArtifact(
              appId: appId,
              artifactPath: fixture.path,
              releaseId: releaseId,
              arch: arch,
              platform: platform,
              hash: hash,
              canSideload: canSideload,
              podfileLockHash: null,
              signing: const ArtifactSigningRequest(
                mode: ReleaseSigningMode.managed,
                keyId: 7,
              ),
            );
          } on Exception {
            // ignore
          }

          final request =
              verify(() => httpClient.send(captureAny())).captured.single
                  as http.MultipartRequest;
          expect(
            request.fields['signing'],
            equals('{"mode":"managed","key_id":7}'),
          );
        });
      });

      group('when podfileLockHash is provided', () {
        test('makes the correct request', () async {
          final tempDir = Directory.systemTemp.createTempSync();
          final fixture = File(path.join(tempDir.path, 'release.txt'))
            ..createSync()
            ..writeAsStringSync('hello');

          try {
            await codePushClient.createReleaseArtifact(
              appId: appId,
              artifactPath: fixture.path,
              releaseId: releaseId,
              arch: arch,
              platform: platform,
              hash: hash,
              canSideload: canSideload,
              podfileLockHash: podfileLockHash,
            );
          } on Exception {
            // ignore
          }

          final request =
              verify(() => httpClient.send(captureAny())).captured.single
                  as http.MultipartRequest;
          expect(request.method, equals('POST'));
          expect(
            request.url,
            equals(v1('apps/$appId/releases/$releaseId/artifacts')),
          );
          expect(request.hasHeaders(expectedHeaders), isTrue);
          expect(request.fields, <String, String>{
            'arch': arch,
            'platform': platform.name,
            'hash': hash,
            'filename': 'release.txt',
            'can_sideload': 'true',
            'size': '$size',
            'podfile_lock_hash': podfileLockHash,
          });
        });
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
          codePushClient.createReleaseArtifact(
            appId: appId,
            artifactPath: fixture.path,
            releaseId: releaseId,
            arch: arch,
            platform: platform,
            hash: hash,
            canSideload: canSideload,
            podfileLockHash: null,
          ),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessageFor(
                HttpStatus.failedDependency,
              ),
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
              podfileLockHash: null,
            ),
            throwsA(isA<CodePushNotFoundException>()),
          );
        },
      );

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
              podfileLockHash: null,
            ),
            throwsA(isA<CodePushConflictException>()),
          );
        },
      );

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
            podfileLockHash: null,
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
                  const CreateReleaseArtifactResponse(
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
          http.StreamedResponse(const Stream.empty(), HttpStatus.badRequest),
        ];
        when(
          () => httpClient.send(any()),
        ).thenAnswer((_) async => responses.removeAt(0));

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
            podfileLockHash: null,
          ),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              contains('Failed to upload artifact'),
            ),
          ),
        );
        final request =
            verify(() => httpClient.send(captureAny())).captured.last
                as http.BaseRequest;
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
                  const CreateReleaseArtifactResponse(
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
          http.StreamedResponse(const Stream.empty(), HttpStatus.noContent),
        ];
        when(
          () => httpClient.send(any()),
        ).thenAnswer((_) async => responses.removeAt(0));

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
            podfileLockHash: podfileLockHash,
          ),
          completes,
        );

        final request =
            verify(() => httpClient.send(captureAny())).captured.first
                as http.MultipartRequest;

        expect(
          request.url,
          codePushClient.hostedUri.replace(
            path: '/api/v1/apps/$appId/releases/$releaseId/artifacts',
          ),
        );
      });

      test('uploads via a resumable session when the server '
          'selects resumable', () async {
        const artifactId = 42;
        const sessionUrl = 'https://storage.googleapis.com/session?upload_id=a';
        final responses = [
          http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(
                  const CreateReleaseArtifactResponse(
                    id: artifactId,
                    releaseId: releaseId,
                    arch: arch,
                    platform: platform,
                    hash: hash,
                    size: size,
                    url: sessionUrl,
                    uploadMethod: ArtifactUploadMethod.resumable,
                  ),
                ),
              ),
            ),
            HttpStatus.ok,
          ),
          http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
        ];
        when(
          () => httpClient.send(any()),
        ).thenAnswer((_) async => responses.removeAt(0));

        final tempDir = Directory.systemTemp.createTempSync();
        final fixture = File(path.join(tempDir.path, 'release.txt'))
          ..writeAsBytesSync([1, 2, 3, 4, 5]);

        await expectLater(
          codePushClient.createReleaseArtifact(
            appId: appId,
            artifactPath: fixture.path,
            releaseId: releaseId,
            arch: arch,
            platform: platform,
            hash: hash,
            canSideload: canSideload,
            podfileLockHash: podfileLockHash,
          ),
          completes,
        );

        final requests = verify(
          () => httpClient.send(captureAny()),
        ).captured.cast<http.BaseRequest>();
        expect(requests, hasLength(2));
        final uploadRequest = requests.last;
        expect(uploadRequest.method, equals('PUT'));
        expect(uploadRequest.url, equals(Uri.parse(sessionUrl)));
        expect(uploadRequest.headers['content-range'], equals('bytes 0-4/5'));
      });

      group('resumable upload driver', () {
        const sessionUrl = 'https://storage.googleapis.com/session?id=abc';

        http.StreamedResponse resumableMeta() => http.StreamedResponse(
          Stream.value(
            utf8.encode(
              json.encode(
                const CreateReleaseArtifactResponse(
                  id: 42,
                  releaseId: releaseId,
                  arch: arch,
                  platform: platform,
                  hash: hash,
                  size: size,
                  url: sessionUrl,
                  uploadMethod: ArtifactUploadMethod.resumable,
                ),
              ),
            ),
          ),
          HttpStatus.ok,
        );

        String fiveByteFixture() {
          final dir = Directory.systemTemp.createTempSync();
          return (File(
            path.join(dir.path, 'release.txt'),
          )..writeAsBytesSync([1, 2, 3, 4, 5])).path;
        }

        void stubActions(
          List<Future<http.StreamedResponse> Function()> actions,
        ) {
          when(
            () => httpClient.send(any()),
          ).thenAnswer((_) => actions.removeAt(0)());
        }

        Future<void> upload(String artifactPath) =>
            codePushClient.createReleaseArtifact(
              appId: appId,
              artifactPath: artifactPath,
              releaseId: releaseId,
              arch: arch,
              platform: platform,
              hash: hash,
              canSideload: canSideload,
              podfileLockHash: null,
            );

        List<http.BaseRequest> capturedPuts() =>
            verify(
                  () => httpClient.send(captureAny()),
                ).captured
                .cast<http.BaseRequest>()
                .where((r) => r.method == 'PUT')
                .toList();

        test('continues to the next chunk on a 308 response', () async {
          stubActions([
            () async => resumableMeta(),
            () async => http.StreamedResponse(
              const Stream.empty(),
              308,
              headers: const {'range': 'bytes=0-2'},
            ),
            () async =>
                http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
          ]);

          await expectLater(upload(fiveByteFixture()), completes);

          final puts = capturedPuts();
          expect(puts, hasLength(2));
          expect(puts[0].headers['content-range'], 'bytes 0-4/5');
          expect(puts[1].headers['content-range'], 'bytes 3-4/5');
        });

        test('throws when a chunk returns an error status', () async {
          stubActions([
            () async => resumableMeta(),
            () async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.badRequest,
            ),
          ]);

          await expectLater(
            upload(fiveByteFixture()),
            throwsA(
              isA<CodePushException>().having(
                (e) => e.message,
                'message',
                contains('Failed to upload artifact'),
              ),
            ),
          );
        });

        test(
          'queries the offset and resumes after a network failure',
          () async {
            stubActions([
              () async => resumableMeta(),
              () async => throw http.ClientException('connection reset'),
              () async => http.StreamedResponse(
                const Stream.empty(),
                308,
                headers: const {'range': 'bytes=0-1'},
              ),
              () async =>
                  http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
            ]);

            await expectLater(upload(fiveByteFixture()), completes);

            final puts = capturedPuts();
            // failed chunk, status query, resumed chunk from offset 2.
            expect(puts, hasLength(3));
            expect(puts[1].headers['content-range'], 'bytes */5');
            expect(puts[2].headers['content-range'], 'bytes 2-4/5');
          },
        );

        test('throws when the status query returns an error', () async {
          stubActions([
            () async => resumableMeta(),
            () async => throw http.ClientException('connection reset'),
            () async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.badRequest,
            ),
          ]);

          await expectLater(
            upload(fiveByteFixture()),
            throwsA(isA<CodePushException>()),
          );
        });

        test('restarts from the beginning on a 308 with no range', () async {
          stubActions([
            () async => resumableMeta(),
            // 308 without a `range` header: GCS stored nothing, restart at 0.
            () async => http.StreamedResponse(const Stream.empty(), 308),
            () async =>
                http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
          ]);

          await expectLater(upload(fiveByteFixture()), completes);

          final puts = capturedPuts();
          expect(puts, hasLength(2));
          expect(puts[0].headers['content-range'], 'bytes 0-4/5');
          // Restarts from offset 0 rather than advancing.
          expect(puts[1].headers['content-range'], 'bytes 0-4/5');
        });

        test('throws when a 308 never makes forward progress', () async {
          // A session stuck at offset 0 keeps returning a 308 with no range;
          // the upload must give up rather than spin forever.
          stubActions([
            () async => resumableMeta(),
            for (var i = 0; i < 6; i++)
              () async => http.StreamedResponse(const Stream.empty(), 308),
          ]);

          await expectLater(
            upload(fiveByteFixture()),
            throwsA(isA<CodePushException>()),
          );
        });

        test('queries the offset and resumes after a 5xx', () async {
          stubActions([
            () async => resumableMeta(),
            () async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.serviceUnavailable,
            ),
            () async => http.StreamedResponse(
              const Stream.empty(),
              308,
              headers: const {'range': 'bytes=0-1'},
            ),
            () async =>
                http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
          ]);

          await expectLater(upload(fiveByteFixture()), completes);

          final puts = capturedPuts();
          // failed chunk, status query, resumed chunk from offset 2.
          expect(puts, hasLength(3));
          expect(puts[0].headers['content-range'], 'bytes 0-4/5');
          expect(puts[1].headers['content-range'], 'bytes */5');
          expect(puts[2].headers['content-range'], 'bytes 2-4/5');
        });

        test('throws when a 5xx persists through the status query', () async {
          stubActions([
            () async => resumableMeta(),
            () async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.serviceUnavailable,
            ),
            // The status query also fails, so we surface the error.
            () async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.serviceUnavailable,
            ),
          ]);

          await expectLater(
            upload(fiveByteFixture()),
            throwsA(isA<CodePushException>()),
          );
        });

        test('throws after exhausting retries on repeated 5xx', () async {
          // Each chunk PUT fails with a 5xx while the status query reports no
          // forward progress, so failures accumulate until we give up.
          final actions = <Future<http.StreamedResponse> Function()>[
            () async => resumableMeta(),
          ];
          for (var i = 0; i < 6; i++) {
            actions
              ..add(
                () async => http.StreamedResponse(
                  const Stream.empty(),
                  HttpStatus.serviceUnavailable,
                ),
              )
              ..add(
                () async => http.StreamedResponse(
                  const Stream.empty(),
                  308,
                  headers: const {'range': 'bytes=0-1'},
                ),
              );
          }
          stubActions(actions);

          await expectLater(
            upload(fiveByteFixture()),
            throwsA(isA<CodePushException>()),
          );
        });
      });
    });

    group('createApp', () {
      test('makes the correct request', () async {
        codePushClient
            .createApp(organizationId: organizationId, displayName: displayName)
            .ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
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
          codePushClient.createApp(
            organizationId: organizationId,
            displayName: displayName,
          ),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessageFor(HttpStatus.badRequest),
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
          codePushClient.createApp(
            organizationId: organizationId,
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
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(const App(id: appId, displayName: displayName)),
              ),
            ),
            HttpStatus.ok,
          ),
        );

        await expectLater(
          codePushClient.createApp(
            organizationId: organizationId,
            displayName: displayName,
          ),
          completion(
            equals(
              isA<App>()
                  .having((a) => a.id, 'id', appId)
                  .having((a) => a.displayName, 'displayName', displayName),
            ),
          ),
        );

        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;

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
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
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
              CodePushClient.unknownErrorMessageFor(HttpStatus.badRequest),
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
                  const Channel(id: channelId, appId: appId, name: channel),
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

        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;

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
              metadata: {'foo': 'bar'},
            )
            .ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
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
            metadata: {'foo': 'bar'},
          ),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessageFor(HttpStatus.badRequest),
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
            metadata: {'foo': 'bar'},
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
                json.encode(const Patch(id: patchId, number: patchNumber)),
              ),
            ),
            HttpStatus.ok,
          ),
        );

        await expectLater(
          codePushClient.createPatch(
            appId: appId,
            releaseId: releaseId,
            metadata: {'foo': 'bar'},
          ),
          completion(
            equals(
              isA<Patch>()
                  .having((c) => c.id, 'id', patchId)
                  .having((c) => c.number, 'number', patchNumber),
            ),
          ),
        );

        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;

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
              flutterVersion: flutterVersion,
              displayName: displayName,
            )
            .ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
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
            flutterVersion: flutterVersion,
            displayName: displayName,
          ),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessageFor(HttpStatus.badRequest),
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
            flutterVersion: flutterVersion,
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
                      flutterVersion: flutterVersion,
                      displayName: displayName,
                      platforms: const {},
                      createdAt: DateTime.utc(2023),
                      updatedAt: DateTime.utc(2023),
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
            flutterVersion: flutterVersion,
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
                  .having(
                    (r) => r.flutterVersion,
                    'flutterVersion',
                    flutterVersion,
                  )
                  .having((r) => r.displayName, 'displayName', displayName)
                  .having(
                    (r) => r.platforms,
                    'platforms',
                    isEmpty,
                  ),
            ),
          ),
        );

        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;

        expect(
          request.url,
          codePushClient.hostedUri.replace(
            path: '/api/v1/apps/$appId/releases',
          ),
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
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
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
              CodePushClient.unknownErrorMessageFor(HttpStatus.badRequest),
            ),
          ),
        );
      });

      test('completes when the server responds with a 204', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.noContent),
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

    group('archiveApp', () {
      test('makes the correct request', () async {
        codePushClient.archiveApp(appId: appId).ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.Request;
        expect(request.method, equals('POST'));
        expect(request.url, equals(v1('apps/$appId/archive')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
        expect(request.body, isEmpty);
      });

      test('throws an exception if the http request fails', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.archiveApp(appId: appId),
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
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.noContent),
        );

        await expectLater(codePushClient.archiveApp(appId: appId), completes);
      });
    });

    group('deleteApp', () {
      test('makes the correct request', () async {
        codePushClient.deleteApp(appId: appId).ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
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
              CodePushClient.unknownErrorMessageFor(
                HttpStatus.failedDependency,
              ),
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
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.noContent),
        );

        await codePushClient.deleteApp(appId: appId);

        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;

        expect(
          request.url,
          codePushClient.hostedUri.replace(path: '/api/v1/apps/$appId'),
        );
      });
    });

    group('unarchiveApp', () {
      test('makes the correct request', () async {
        codePushClient.unarchiveApp(appId: appId).ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.Request;
        expect(request.method, equals('POST'));
        expect(request.url, equals(v1('apps/$appId/unarchive')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
        expect(request.body, isEmpty);
      });

      test('throws an exception if the http request fails', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.unarchiveApp(appId: appId),
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
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.noContent),
        );

        await expectLater(codePushClient.unarchiveApp(appId: appId), completes);
      });
    });

    group('updateApp', () {
      const displayName = 'New Name';

      test('makes the correct request', () async {
        codePushClient
            .updateApp(appId: appId, displayName: displayName)
            .ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.Request;
        expect(request.method, equals('PATCH'));
        expect(request.url, equals(v1('apps/$appId')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
        expect(json.decode(request.body), equals({'name': displayName}));
      });

      test('throws an exception if the http request fails', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.updateApp(appId: appId, displayName: displayName),
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
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
        );

        await expectLater(
          codePushClient.updateApp(appId: appId, displayName: displayName),
          completes,
        );
      });
    });

    group('updateCurrentUser', () {
      test('makes the correct request', () async {
        codePushClient.updateCurrentUser(displayName: 'Jane Doe').ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.Request;
        expect(request.method, equals('PATCH'));
        expect(request.url, equals(v1('users/me')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
        expect(
          json.decode(request.body),
          equals({'display_name': 'Jane Doe'}),
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
          codePushClient.updateCurrentUser(displayName: 'Jane Doe'),
          throwsA(isA<CodePushException>()),
        );
      });

      test('completes when request succeeds', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.noContent),
        );

        await expectLater(
          codePushClient.updateCurrentUser(displayName: 'Jane Doe'),
          completes,
        );
      });
    });

    group('getEmailNotificationsEnabled', () {
      test('makes the correct request', () async {
        codePushClient.getEmailNotificationsEnabled().ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.Request;
        expect(request.method, equals('GET'));
        expect(request.url, equals(v1('users/me/notification_preferences')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the http request fails', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.getEmailNotificationsEnabled(),
          throwsA(isA<CodePushException>()),
        );
      });

      test('returns the setting', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode({
                  'preferences': {'are_email_notifications_enabled': false},
                }),
              ),
            ),
            HttpStatus.ok,
          ),
        );

        await expectLater(
          codePushClient.getEmailNotificationsEnabled(),
          completion(isFalse),
        );
      });
    });

    group('setEmailNotificationsEnabled', () {
      test('makes the correct request', () async {
        codePushClient.setEmailNotificationsEnabled(enabled: false).ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.Request;
        expect(request.method, equals('PATCH'));
        expect(request.url, equals(v1('users/me/notification_preferences')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
        expect(
          json.decode(request.body),
          equals({'are_email_notifications_enabled': false}),
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
          codePushClient.setEmailNotificationsEnabled(enabled: true),
          throwsA(isA<CodePushException>()),
        );
      });

      test('completes when request succeeds', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.noContent),
        );

        await expectLater(
          codePushClient.setEmailNotificationsEnabled(enabled: true),
          completes,
        );
      });
    });

    group('transferApp', () {
      const organizationId = 42;

      test('makes the correct request', () async {
        codePushClient
            .transferApp(organizationId: organizationId, appId: appId)
            .ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.Request;
        expect(request.method, equals('POST'));
        expect(request.url, equals(v1('organizations/$organizationId/apps')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
        // Sent as snake_case; do not "fix" this to camelCase.
        expect(json.decode(request.body), equals({'app_id': appId}));
      });

      test('throws an exception if the http request fails', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.transferApp(
            organizationId: organizationId,
            appId: appId,
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
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
        );

        await expectLater(
          codePushClient.transferApp(
            organizationId: organizationId,
            appId: appId,
          ),
          completes,
        );
      });
    });

    group('deleteChannel', () {
      const channelId = 7;

      test('makes the correct request', () async {
        codePushClient
            .deleteChannel(appId: appId, channelId: channelId)
            .ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
        expect(request.method, equals('DELETE'));
        expect(request.url, equals(v1('apps/$appId/channels/$channelId')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the http request fails', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.deleteChannel(appId: appId, channelId: channelId),
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
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.noContent),
        );

        await expectLater(
          codePushClient.deleteChannel(appId: appId, channelId: channelId),
          completes,
        );
      });
    });

    group('deleteRelease', () {
      const releaseId = 42;

      test('makes the correct request', () async {
        codePushClient
            .deleteRelease(appId: appId, releaseId: releaseId)
            .ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
        expect(request.method, equals('DELETE'));
        expect(request.url, equals(v1('apps/$appId/releases/$releaseId')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws CodePushForbiddenException on 403', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.forbidden,
          ),
        );

        expect(
          codePushClient.deleteRelease(appId: appId, releaseId: releaseId),
          throwsA(
            isA<CodePushForbiddenException>().having(
              (e) => e.message,
              'message',
              errorResponse.message,
            ),
          ),
        );
      });

      test('throws CodePushNotFoundException on 404', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.notFound,
          ),
        );

        expect(
          codePushClient.deleteRelease(appId: appId, releaseId: releaseId),
          throwsA(isA<CodePushNotFoundException>()),
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
          codePushClient.deleteRelease(appId: appId, releaseId: releaseId),
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
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.noContent),
        );

        await expectLater(
          codePushClient.deleteRelease(appId: appId, releaseId: releaseId),
          completes,
        );
      });
    });

    group('deleteReleaseArtifacts', () {
      const releaseId = 42;

      test('makes the correct request', () async {
        codePushClient
            .deleteReleaseArtifacts(
              appId: appId,
              releaseId: releaseId,
              platform: ReleasePlatform.ios,
            )
            .ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
        expect(request.method, equals('DELETE'));
        expect(
          request.url,
          equals(v1('apps/$appId/releases/$releaseId/artifacts?platform=ios')),
        );
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws CodePushForbiddenException on 403', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.forbidden,
          ),
        );

        expect(
          codePushClient.deleteReleaseArtifacts(
            appId: appId,
            releaseId: releaseId,
            platform: ReleasePlatform.ios,
          ),
          throwsA(
            isA<CodePushForbiddenException>().having(
              (e) => e.message,
              'message',
              errorResponse.message,
            ),
          ),
        );
      });

      test('throws CodePushNotFoundException on 404', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
            HttpStatus.notFound,
          ),
        );

        expect(
          codePushClient.deleteReleaseArtifacts(
            appId: appId,
            releaseId: releaseId,
            platform: ReleasePlatform.ios,
          ),
          throwsA(isA<CodePushNotFoundException>()),
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
          codePushClient.deleteReleaseArtifacts(
            appId: appId,
            releaseId: releaseId,
            platform: ReleasePlatform.ios,
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
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.noContent),
        );

        await expectLater(
          codePushClient.deleteReleaseArtifacts(
            appId: appId,
            releaseId: releaseId,
            platform: ReleasePlatform.ios,
          ),
          completes,
        );
      });
    });

    group('getApp', () {
      final app = AppMetadata(
        appId: 'app-id',
        displayName: 'Shorebird Example',
        createdAt: DateTime.utc(2022),
        updatedAt: DateTime.utc(2023),
      );

      test('makes the correct request', () async {
        codePushClient.getApp(appId: 'app-id').ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
        expect(request.method, equals('GET'));
        expect(request.url, equals(v1('apps/app-id')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('returns null if the response is a 404', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.notFound),
        );

        expect(await codePushClient.getApp(appId: 'app-id'), isNull);
      });

      test('throws an exception if the http request fails', () {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.getApp(appId: 'app-id'),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessageFor(
                HttpStatus.failedDependency,
              ),
            ),
          ),
        );
      });

      test('returns the app when the request succeeds', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode(json.encode(app))),
            HttpStatus.ok,
          ),
        );

        expect(await codePushClient.getApp(appId: 'app-id'), equals(app));
      });
    });

    group('getSigningKey', () {
      const signingKey = SigningKey(id: 7, publicKeyPem: 'pem');

      test('makes the correct request', () async {
        codePushClient.getSigningKey(appId: 'app-id').ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
        expect(request.method, equals('GET'));
        expect(request.url, equals(v1('apps/app-id/signing-key')));
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('throws an exception if the http request fails', () {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.serviceUnavailable,
          ),
        );

        expect(
          codePushClient.getSigningKey(appId: 'app-id'),
          throwsA(isA<CodePushException>()),
        );
      });

      test('returns the key when the request succeeds', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                json.encode(
                  const GetSigningKeyResponse(signingKey: signingKey),
                ),
              ),
            ),
            HttpStatus.ok,
          ),
        );

        expect(
          await codePushClient.getSigningKey(appId: 'app-id'),
          equals(signingKey),
        );
      });
    });

    group('getApps', () {
      test('makes the correct request', () async {
        codePushClient.getApps().ignore();
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
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
              CodePushClient.unknownErrorMessageFor(
                HttpStatus.failedDependency,
              ),
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
            createdAt: DateTime.utc(2022),
            updatedAt: DateTime.utc(2023),
          ),
          AppMetadata(
            appId: '2',
            displayName: 'Shorebird Clock',
            createdAt: DateTime.utc(2022),
            updatedAt: DateTime.utc(2023),
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
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
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
              CodePushClient.unknownErrorMessageFor(
                HttpStatus.failedDependency,
              ),
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
          const Channel(id: 0, appId: '1', name: 'stable'),
          const Channel(id: 1, appId: '2', name: 'development'),
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
          final request =
              verify(() => httpClient.send(captureAny())).captured.single
                  as http.BaseRequest;
          expect(request.method, equals('GET'));
          expect(request.url, equals(v1('apps/$appId/releases')));
          expect(request.hasHeaders(expectedHeaders), isTrue);
        });

        test('when sideloadableOnly is true', () async {
          codePushClient
              .getReleases(appId: appId, sideloadableOnly: true)
              .ignore();
          final request =
              verify(() => httpClient.send(captureAny())).captured.single
                  as http.BaseRequest;
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
              CodePushClient.unknownErrorMessageFor(
                HttpStatus.failedDependency,
              ),
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
              utf8.encode(json.encode(const GetReleasesResponse(releases: []))),
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
            flutterVersion: flutterVersion,
            displayName: 'v1.0.0',
            platforms: const {
              ReleasePlatform.android: ReleasePlatformDetails(
                status: ReleaseStatus.draft,
              ),
            },
            createdAt: DateTime.utc(2022),
            updatedAt: DateTime.utc(2023),
          ),
          Release(
            id: 1,
            appId: '2',
            version: '1.0.1',
            flutterRevision: flutterRevision,
            flutterVersion: flutterVersion,
            displayName: 'v1.0.1',
            platforms: const {},
            createdAt: DateTime.utc(2022),
            updatedAt: DateTime.utc(2023),
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

    group('getPatches', () {
      group('when request is not successful', () {
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.failedDependency,
            ),
          );
        });

        test('throws exception', () async {
          expect(
            () async => codePushClient.getPatches(appId: appId, releaseId: 123),
            throwsA(
              isA<CodePushException>().having(
                (e) => e.message,
                'message',
                CodePushClient.unknownErrorMessageFor(
                  HttpStatus.failedDependency,
                ),
              ),
            ),
          );
        });
      });

      group('when request is successful', () {
        late GetReleasePatchesResponse response;
        late ReleasePatch patch;

        setUp(() {
          patch = const ReleasePatch(
            id: 0,
            number: 1,
            channel: 'stable',
            isRolledBack: false,
            artifacts: [],
          );
          response = GetReleasePatchesResponse(patches: [patch]);
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(utf8.encode(json.encode(response))),
              HttpStatus.ok,
            ),
          );
        });

        test('deserializes GetReleasePatchesResponse', () async {
          final patches = await codePushClient.getPatches(
            appId: appId,
            releaseId: 123,
          );
          expect(patches, equals([patch]));
        });
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
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
        expect(request.method, equals('GET'));
        expect(
          request.url,
          equals(
            v1(
              'apps/$appId/releases/$releaseId/artifacts?arch=$arch&platform=${platform.name}',
            ),
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
              CodePushClient.unknownErrorMessageFor(
                HttpStatus.failedDependency,
              ),
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
          const ReleaseArtifact(
            id: 0,
            releaseId: releaseId,
            arch: arch,
            platform: platform,
            url: 'https://example.com',
            hash: '#',
            size: 42,
            canSideload: true,
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
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
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
              CodePushClient.unknownErrorMessageFor(HttpStatus.badRequest),
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
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.created),
        );

        await expectLater(
          codePushClient.promotePatch(
            appId: appId,
            patchId: patchId,
            channelId: channelId,
          ),
          completes,
        );

        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;

        expect(
          request.url,
          codePushClient.hostedUri.replace(
            path: '/api/v1/apps/$appId/patches/promote',
          ),
        );
      });
    });

    group('rollbackPatch', () {
      const releaseId = 7;
      const patchId = 11;

      test('makes the correct request', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.noContent,
          ),
        );

        await codePushClient.rollbackPatch(
          appId: appId,
          releaseId: releaseId,
          patchId: patchId,
        );

        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
        expect(request.method, equals('POST'));
        expect(
          request.url,
          equals(
            v1('apps/$appId/releases/$releaseId/patches/$patchId/rollback'),
          ),
        );
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('returns false on 304 Not Modified (idempotent)', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.notModified,
          ),
        );

        await expectLater(
          codePushClient.rollbackPatch(
            appId: appId,
            releaseId: releaseId,
            patchId: patchId,
          ),
          completion(isFalse),
        );
      });

      test('returns true on 204 No Content', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.noContent,
          ),
        );

        await expectLater(
          codePushClient.rollbackPatch(
            appId: appId,
            releaseId: releaseId,
            patchId: patchId,
          ),
          completion(isTrue),
        );
      });

      test('throws an exception if the http request fails (unknown)', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.badRequest,
          ),
        );

        expect(
          codePushClient.rollbackPatch(
            appId: appId,
            releaseId: releaseId,
            patchId: patchId,
          ),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessageFor(HttpStatus.badRequest),
            ),
          ),
        );
      });

      test(
        'throws a parsed exception on a structured error response',
        () async {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
              HttpStatus.failedDependency,
            ),
          );

          expect(
            codePushClient.rollbackPatch(
              appId: appId,
              releaseId: releaseId,
              patchId: patchId,
            ),
            throwsA(
              isA<CodePushException>().having(
                (e) => e.message,
                'message',
                errorResponse.message,
              ),
            ),
          );
        },
      );
    });

    group('rollforwardPatch', () {
      const releaseId = 7;
      const patchId = 11;

      test('makes the correct request', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.noContent,
          ),
        );

        await codePushClient.rollforwardPatch(
          appId: appId,
          releaseId: releaseId,
          patchId: patchId,
        );

        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
        expect(request.method, equals('POST'));
        expect(
          request.url,
          equals(
            v1('apps/$appId/releases/$releaseId/patches/$patchId/rollforward'),
          ),
        );
        expect(request.hasHeaders(expectedHeaders), isTrue);
      });

      test('returns false on 304 Not Modified (idempotent)', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.notModified,
          ),
        );

        await expectLater(
          codePushClient.rollforwardPatch(
            appId: appId,
            releaseId: releaseId,
            patchId: patchId,
          ),
          completion(isFalse),
        );
      });

      test('returns true on 204 No Content', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.noContent,
          ),
        );

        await expectLater(
          codePushClient.rollforwardPatch(
            appId: appId,
            releaseId: releaseId,
            patchId: patchId,
          ),
          completion(isTrue),
        );
      });

      test('throws an exception if the http request fails (unknown)', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.badRequest,
          ),
        );

        expect(
          codePushClient.rollforwardPatch(
            appId: appId,
            releaseId: releaseId,
            patchId: patchId,
          ),
          throwsA(
            isA<CodePushException>().having(
              (e) => e.message,
              'message',
              CodePushClient.unknownErrorMessageFor(HttpStatus.badRequest),
            ),
          ),
        );
      });

      test(
        'throws a parsed exception on a structured error response',
        () async {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(utf8.encode(json.encode(errorResponse.toJson()))),
              HttpStatus.failedDependency,
            ),
          );

          expect(
            codePushClient.rollforwardPatch(
              appId: appId,
              releaseId: releaseId,
              patchId: patchId,
            ),
            throwsA(
              isA<CodePushException>().having(
                (e) => e.message,
                'message',
                errorResponse.message,
              ),
            ),
          );
        },
      );
    });

    group('getOrganizationMemberships', () {
      group('when response is not success', () {
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.failedDependency,
            ),
          );
        });

        test('throws exception', () async {
          expect(
            () async => codePushClient.getOrganizationMemberships(),
            throwsA(
              isA<CodePushException>().having(
                (e) => e.message,
                'message',
                CodePushClient.unknownErrorMessageFor(
                  HttpStatus.failedDependency,
                ),
              ),
            ),
          );
        });
      });

      group('when response is successful', () {
        late GetOrganizationsResponse response;
        late OrganizationMembership membership;

        setUp(() {
          membership = OrganizationMembership(
            role: Role.admin,
            organization: organizationForTest(),
          );
          response = GetOrganizationsResponse(organizations: [membership]);
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(utf8.encode(json.encode(response))),
              HttpStatus.ok,
            ),
          );
        });

        test('deserializes GetOrganizationMembershipsResponse', () async {
          final memberships = await codePushClient.getOrganizationMemberships();
          expect(memberships, equals([membership]));
        });
      });
    });

    group('getOrganizationApps', () {
      const organizationId = 42;

      group('when response is not success', () {
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.failedDependency,
            ),
          );
        });

        test('throws exception', () async {
          expect(
            () async => codePushClient.getOrganizationApps(
              organizationId: organizationId,
            ),
            throwsA(
              isA<CodePushException>().having(
                (e) => e.message,
                'message',
                CodePushClient.unknownErrorMessageFor(
                  HttpStatus.failedDependency,
                ),
              ),
            ),
          );
        });
      });

      group('when response is successful', () {
        final app = AppMetadata(
          appId: 'app-id',
          displayName: 'My App',
          createdAt: DateTime.utc(2023),
          updatedAt: DateTime.utc(2023),
        );

        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  json.encode(GetOrganizationAppsResponse(apps: [app])),
                ),
              ),
              HttpStatus.ok,
            ),
          );
        });

        test('requests the organization apps and returns them', () async {
          final apps = await codePushClient.getOrganizationApps(
            organizationId: organizationId,
          );
          expect(apps, equals([app]));
          final request =
              verify(() => httpClient.send(captureAny())).captured.single
                  as http.BaseRequest;
          expect(request.method, equals('GET'));
          expect(
            request.url,
            equals(v1('organizations/$organizationId/apps')),
          );
        });
      });
    });

    group('getReceivedInvitations', () {
      ReceivedInvitation invitation(String id) => ReceivedInvitation(
        id: id,
        organizationId: 1,
        targetName: 'Acme',
        inviterEmail: 'admin@shorebird.dev',
        role: Role.developer,
        createdAt: DateTime.utc(2026, 4, 20),
        expiresAt: DateTime.utc(2026, 5, 4),
      );

      http.StreamedResponse page(
        List<ReceivedInvitation> invitations, {
        String? nextCursor,
      }) => http.StreamedResponse(
        Stream.value(
          utf8.encode(
            json.encode(
              GetReceivedInvitationsResponse(
                invitations: invitations,
                nextCursor: nextCursor,
              ).toJson(),
            ),
          ),
        ),
        HttpStatus.ok,
      );

      test('throws when the response is not success', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.failedDependency,
          ),
        );

        expect(
          codePushClient.getReceivedInvitations,
          throwsA(isA<CodePushException>()),
        );
      });

      test('stops at an empty page even if it carries a cursor', () async {
        when(
          () => httpClient.send(any()),
        ).thenAnswer((_) async => page([], nextCursor: 'again'));

        final invitations = await codePushClient.getReceivedInvitations();

        expect(invitations, isEmpty);
        verify(() => httpClient.send(any())).called(1);
      });

      test('follows next_cursor through every page', () async {
        final responses = [
          page([invitation('a')], nextCursor: 'next'),
          page([invitation('b')]),
        ];
        when(
          () => httpClient.send(any()),
        ).thenAnswer((_) async => responses.removeAt(0));

        final invitations = await codePushClient.getReceivedInvitations();

        expect(invitations.map((i) => i.id), equals(['a', 'b']));
        final requests = verify(
          () => httpClient.send(captureAny()),
        ).captured.cast<http.BaseRequest>();
        expect(requests.map((r) => r.method), everyElement(equals('GET')));
        expect(
          requests.map((r) => r.url),
          equals([
            v1('invitations').replace(queryParameters: {'per_page': '100'}),
            v1('invitations').replace(
              queryParameters: {'per_page': '100', 'cursor': 'next'},
            ),
          ]),
        );
      });
    });

    for (final (name, call) in [
      (
        'acceptInvitation',
        (CodePushClient client) => client.acceptInvitation(invitationId: 'id'),
      ),
      (
        'declineInvitation',
        (CodePushClient client) => client.declineInvitation(invitationId: 'id'),
      ),
    ]) {
      group(name, () {
        final action = name.replaceAll('Invitation', '');

        test('posts to the invitation', () async {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.noContent,
            ),
          );

          await call(codePushClient);

          final request =
              verify(() => httpClient.send(captureAny())).captured.single
                  as http.BaseRequest;
          expect(request.method, equals('POST'));
          expect(request.url, equals(v1('invitations/id/$action')));
        });

        test('throws the API error when the response is not success', () async {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  json.encode(
                    const ErrorResponse(
                      code: 'invitation_gone',
                      message: 'This invitation is no longer valid.',
                    ).toJson(),
                  ),
                ),
              ),
              HttpStatus.gone,
            ),
          );

          expect(
            () => call(codePushClient),
            throwsA(
              isA<CodePushException>().having(
                (e) => e.code,
                'code',
                'invitation_gone',
              ),
            ),
          );
        });
      });
    }

    group('getPlanLevel', () {
      group('when request fails', () {
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.failedDependency,
            ),
          );
        });

        test('throws exception', () async {
          expect(
            () async => codePushClient.getPlanLevel(),
            throwsA(
              isA<CodePushException>().having(
                (e) => e.message,
                'message',
                CodePushClient.unknownErrorMessageFor(
                  HttpStatus.failedDependency,
                ),
              ),
            ),
          );
        });
      });

      group('when request succeeds', () {
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(utf8.encode('{"level": "enterprise"}')),
              HttpStatus.ok,
            ),
          );
        });

        test('returns the level', () async {
          expect(await codePushClient.getPlanLevel(), equals('enterprise'));
        });
      });

      group('when the response has no level', () {
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(utf8.encode('{}')),
              HttpStatus.ok,
            ),
          );
        });

        test('returns null', () async {
          expect(await codePushClient.getPlanLevel(), isNull);
        });
      });
    });

    group('getGCPUploadSpeedTestUrl', () {
      group('when request fails', () {
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.failedDependency,
            ),
          );
        });

        test('throws exception', () async {
          expect(
            () async => codePushClient.getGCPUploadSpeedTestUrl(),
            throwsA(
              isA<CodePushException>().having(
                (e) => e.message,
                'message',
                CodePushClient.unknownErrorMessageFor(
                  HttpStatus.failedDependency,
                ),
              ),
            ),
          );
        });
      });

      group('when request succeeds', () {
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(
                utf8.encode('{"upload_url": "https://example.com"}'),
              ),
              HttpStatus.ok,
            ),
          );
        });

        test('returns upload_url as parsed Uri', () async {
          final url = await codePushClient.getGCPUploadSpeedTestUrl();
          expect(url, equals(Uri.parse('https://example.com')));
        });
      });
    });

    group('getGCPDownloadSpeedTestUrl', () {
      group('when request fails', () {
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.failedDependency,
            ),
          );
        });

        test('throws exception', () async {
          expect(
            () async => codePushClient.getGCPDownloadSpeedTestUrl(),
            throwsA(
              isA<CodePushException>().having(
                (e) => e.message,
                'message',
                CodePushClient.unknownErrorMessageFor(
                  HttpStatus.failedDependency,
                ),
              ),
            ),
          );
        });
      });

      group('when request succeeds', () {
        setUp(() {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(
                utf8.encode('{"download_url": "https://example.com"}'),
              ),
              HttpStatus.ok,
            ),
          );
        });

        test('returns download_url as parsed Uri', () async {
          final url = await codePushClient.getGCPDownloadSpeedTestUrl();
          expect(url, equals(Uri.parse('https://example.com')));
        });
      });
    });

    group('metrics', () {
      const releaseId = 42;
      final asOf = DateTime.utc(2026, 10, 15);
      final range = MetricsRange(
        start: DateTime.utc(2026, 9, 17),
        end: DateTime.utc(2026, 10, 15),
      );
      final patchMetricResponse = GetPatchMetricResponse(
        asOf: asOf,
        granularity: null,
        current: PatchMetricCurrentWindow(count: 10, range: range),
      );
      final uniqueUsersResponse = GetUniqueUsersResponse(
        asOf: asOf,
        granularity: null,
        current: UniqueUsersCurrentWindow(uniqueUsers: 5, range: range),
        previous: null,
      );
      final versionDistributionResponse = GetVersionDistributionResponse(
        entries: const [
          VersionDistributionEntry(
            releaseVersion: '1.0.0+1',
            deviceCount: 3,
            percentage: 1,
          ),
        ],
        totalDevices: 3,
        activeWindowDays: 28,
        asOf: asOf,
      );
      final newDevicesResponse = GetNewDevicesResponse(
        current: 7,
        previous: 4,
        windowDays: 28,
        asOf: asOf,
      );
      final patchAdoptionResponse = GetPatchAdoptionResponse(
        releaseVersion: '1.0.0+1',
        isLatest: true,
        granularity: null,
        range: range,
        asOf: asOf,
        patches: const [
          PatchAdoptionEntry(
            patchNumber: 1,
            targetPlatforms: [ReleasePlatform.android],
            isRolledBack: false,
            series: [
              PatchAdoptionPoint(
                period: null,
                devices: 1,
                target: 2,
                adoptionPct: .5,
              ),
            ],
          ),
        ],
      );
      final activeHoursResponse = GetActiveHoursResponse(
        hourly: const [ActiveHourEntry(hourUtc: 0, averageActiveDevices: 1.5)],
        recommendedWindowStartUtc: 3,
        recommendedWindowLengthHours: 2,
        busiestHourUtc: 14,
        lookbackDays: 28,
        asOf: asOf,
      );
      final activityHeatmapResponse = GetActivityHeatmapResponse(
        cells: const [
          ActivityHeatmapCell(
            dayOfWeekUtc: 1,
            hourUtc: 0,
            averageActiveDevices: 2,
          ),
        ],
        busiestDayOfWeekUtc: 1,
        busiestHourUtc: 0,
        lookbackDays: 28,
        asOf: asOf,
      );

      // Each case: the request with no optional arguments, the path it
      // should hit, a response body, and how to read it back as JSON.
      final cases =
          <
            ({
              String name,
              Future<Object> Function() call,
              String path,
              Map<String, dynamic> body,
            })
          >[
            (
              name: 'getAppPatchInstalls',
              call: () => codePushClient.getAppPatchInstalls(appId: appId),
              path: 'apps/$appId/metrics/patch-installs',
              body: patchMetricResponse.toJson(),
            ),
            (
              name: 'getReleasePatchInstalls',
              call: () => codePushClient.getReleasePatchInstalls(
                appId: appId,
                releaseId: releaseId,
              ),
              path: 'apps/$appId/releases/$releaseId/metrics/patch-installs',
              body: patchMetricResponse.toJson(),
            ),
            (
              name: 'getAppPatchDownloads',
              call: () => codePushClient.getAppPatchDownloads(appId: appId),
              path: 'apps/$appId/metrics/patch-downloads',
              body: patchMetricResponse.toJson(),
            ),
            (
              name: 'getReleasePatchDownloads',
              call: () => codePushClient.getReleasePatchDownloads(
                appId: appId,
                releaseId: releaseId,
              ),
              path: 'apps/$appId/releases/$releaseId/metrics/patch-downloads',
              body: patchMetricResponse.toJson(),
            ),
            (
              name: 'getUniqueUsers',
              call: () => codePushClient.getUniqueUsers(appId: appId),
              path: 'apps/$appId/metrics/unique-users',
              body: uniqueUsersResponse.toJson(),
            ),
            (
              name: 'getVersionDistribution',
              call: () => codePushClient.getVersionDistribution(appId: appId),
              path: 'apps/$appId/metrics/version-distribution',
              body: versionDistributionResponse.toJson(),
            ),
            (
              name: 'getNewDevices',
              call: () => codePushClient.getNewDevices(appId: appId),
              path: 'apps/$appId/metrics/new-devices',
              body: newDevicesResponse.toJson(),
            ),
            (
              name: 'getPatchAdoption',
              call: () => codePushClient.getPatchAdoption(appId: appId),
              path: 'apps/$appId/metrics/patch-adoption',
              body: patchAdoptionResponse.toJson(),
            ),
            (
              name: 'getActiveHours',
              call: () => codePushClient.getActiveHours(appId: appId),
              path: 'apps/$appId/metrics/active-hours',
              body: activeHoursResponse.toJson(),
            ),
            (
              name: 'getActivityHeatmap',
              call: () => codePushClient.getActivityHeatmap(appId: appId),
              path: 'apps/$appId/metrics/activity-heatmap',
              body: activityHeatmapResponse.toJson(),
            ),
          ];

      for (final c in cases) {
        group(c.name, () {
          test('makes the correct request', () async {
            c.call().ignore();
            final request =
                verify(() => httpClient.send(captureAny())).captured.single
                    as http.BaseRequest;
            expect(request.method, equals('GET'));
            expect(request.url, equals(v1(c.path)));
            expect(request.hasHeaders(expectedHeaders), isTrue);
          });

          test('parses the response', () async {
            when(() => httpClient.send(any())).thenAnswer(
              (_) async => http.StreamedResponse(
                Stream.value(utf8.encode(json.encode(c.body))),
                HttpStatus.ok,
              ),
            );
            final result = await c.call();
            expect((result as dynamic).toJson(), equals(c.body));
          });

          test('throws with the server error code on failure', () async {
            when(() => httpClient.send(any())).thenAnswer(
              (_) async => http.StreamedResponse(
                Stream.value(
                  utf8.encode(
                    json.encode(
                      ErrorResponse(
                        code: 'shorebird_plan_insufficient_tier',
                        message: 'upgrade required',
                        documentationUrl: Uri.parse(
                          'https://docs.shorebird.dev/account/api/',
                        ),
                      ).toJson(),
                    ),
                  ),
                ),
                HttpStatus.forbidden,
              ),
            );
            await expectLater(
              c.call(),
              throwsA(
                isA<CodePushForbiddenException>()
                    .having((e) => e.message, 'message', 'upgrade required')
                    .having(
                      (e) => e.code,
                      'code',
                      'shorebird_plan_insufficient_tier',
                    )
                    .having(
                      (e) => e.documentationUrl,
                      'documentationUrl',
                      Uri.parse('https://docs.shorebird.dev/account/api/'),
                    ),
              ),
            );
          });
        });
      }

      group('query parameters', () {
        final start = DateTime.utc(2026, 9);
        final end = DateTime.utc(2026, 10);

        Future<Uri> capturedUrl(Future<Object> Function() call) async {
          call().ignore();
          final request =
              verify(() => httpClient.send(captureAny())).captured.single
                  as http.BaseRequest;
          return request.url;
        }

        test('patch metrics send start, end, granularity and group_by', () {
          final calls = <Future<Object> Function(), String>{
            () => codePushClient.getAppPatchInstalls(
              appId: appId,
              start: start,
              end: end,
              granularity: 'day',
              groupBy: 'release',
            ): 'release',
            () => codePushClient.getReleasePatchInstalls(
              appId: appId,
              releaseId: releaseId,
              start: start,
              end: end,
              granularity: 'day',
              groupBy: 'patch',
            ): 'patch',
            () => codePushClient.getAppPatchDownloads(
              appId: appId,
              start: start,
              end: end,
              granularity: 'day',
              groupBy: 'release',
            ): 'release',
            () => codePushClient.getReleasePatchDownloads(
              appId: appId,
              releaseId: releaseId,
              start: start,
              end: end,
              granularity: 'day',
              groupBy: 'patch',
            ): 'patch',
          };
          for (final MapEntry(key: call, value: groupBy) in calls.entries) {
            clearInteractions(httpClient);
            expect(
              capturedUrl(call),
              completion(
                isA<Uri>().having((u) => u.queryParameters, 'query', {
                  'start': '2026-09-01T00:00:00.000Z',
                  'end': '2026-10-01T00:00:00.000Z',
                  'granularity': 'day',
                  'group_by': groupBy,
                }),
              ),
            );
          }
        });

        test('getUniqueUsers sends start, end, granularity and group_by', () {
          expect(
            capturedUrl(
              () => codePushClient.getUniqueUsers(
                appId: appId,
                start: start,
                end: end,
                granularity: 'week',
                groupBy: 'platform',
              ),
            ),
            completion(
              isA<Uri>().having((u) => u.queryParameters, 'query', {
                'start': '2026-09-01T00:00:00.000Z',
                'end': '2026-10-01T00:00:00.000Z',
                'granularity': 'week',
                'group_by': 'platform',
              }),
            ),
          );
        });

        test('getPatchAdoption sends release_version and window', () {
          expect(
            capturedUrl(
              () => codePushClient.getPatchAdoption(
                appId: appId,
                releaseVersion: '1.0.0+1',
                start: start,
                end: end,
                granularity: 'hour',
              ),
            ),
            completion(
              isA<Uri>().having((u) => u.queryParameters, 'query', {
                'release_version': '1.0.0+1',
                'start': '2026-09-01T00:00:00.000Z',
                'end': '2026-10-01T00:00:00.000Z',
                'granularity': 'hour',
              }),
            ),
          );
        });

        test('converts non-UTC times to UTC', () {
          final local = DateTime.utc(2026, 9).toLocal();
          expect(
            capturedUrl(
              () => codePushClient.getUniqueUsers(appId: appId, start: local),
            ),
            completion(
              isA<Uri>().having((u) => u.queryParameters, 'query', {
                'start': '2026-09-01T00:00:00.000Z',
              }),
            ),
          );
        });
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
    return headers.entries.every((entry) => headers[entry.key] == entry.value);
  }
}

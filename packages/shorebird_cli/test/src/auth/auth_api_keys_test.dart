import 'dart:convert';
import 'dart:io' hide Platform;

import 'package:googleapis_auth/auth_io.dart' as oauth2;
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart'
    show ApiKeyScope, AuthProvider;
import 'package:test/test.dart';

import '../fakes.dart';
import '../mocks.dart';

void main() {
  group('Auth API key management', () {
    const refreshToken = 'sb_rt_refresh';
    final accessToken = oauth2.AccessToken(
      'Bearer',
      'accessToken',
      DateTime.now().add(const Duration(minutes: 10)).toUtc(),
    );

    late String credentialsDir;
    late http.Client httpClient;
    late ShorebirdLogger logger;
    late Platform platform;
    late ShorebirdEnv shorebirdEnv;
    late Map<String, String> environment;

    setUpAll(() {
      registerFallbackValue(FakeBaseRequest());
    });

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          httpClientRef.overrideWith(() => httpClient),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    Auth buildAuth() => runWithOverrides(
      () => Auth(credentialsDir: credentialsDir, httpClient: httpClient),
    );

    void writeCredentials() {
      File(p.join(credentialsDir, 'credentials.json')).writeAsStringSync(
        jsonEncode(
          oauth2.AccessCredentials(
            accessToken,
            refreshToken,
            const ['openid'],
          ).toJson(),
        ),
      );
    }

    /// Stubs the next HTTP send with [body] and [statusCode], and returns a
    /// sink that captures the request that was sent.
    List<http.BaseRequest> stubSend({
      required String body,
      int statusCode = HttpStatus.ok,
    }) {
      final requests = <http.BaseRequest>[];
      when(() => httpClient.send(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments.first as http.BaseRequest;
        requests.add(request);
        return http.StreamedResponse(
          Stream.value(utf8.encode(body)),
          statusCode,
        );
      });
      return requests;
    }

    setUp(() {
      credentialsDir = Directory.systemTemp.createTempSync().path;
      httpClient = MockHttpClient();
      logger = MockShorebirdLogger();
      platform = MockPlatform();
      shorebirdEnv = MockShorebirdEnv();
      environment = <String, String>{};

      when(() => platform.environment).thenReturn(environment);
      when(
        () => shorebirdEnv.authServiceUri,
      ).thenReturn(Uri.parse('https://auth.shorebird.dev'));
      when(() => shorebirdEnv.hostedUri).thenReturn(null);
    });

    group('without an interactive session', () {
      test('throws when there are no credentials at all', () async {
        final auth = buildAuth();
        await expectLater(
          auth.listApiKeys(),
          throwsA(isA<ApiKeySessionRequiredException>()),
        );
      });

      test('throws when authenticated with an API key', () async {
        environment[shorebirdTokenEnvVar] = 'sb_api_something';
        final auth = buildAuth();

        await expectLater(
          auth.listApiKeys(),
          throwsA(isA<ApiKeySessionRequiredException>()),
        );
        verifyNever(() => httpClient.send(any()));
      });

      test('throws when authenticated with a legacy CI token', () async {
        environment[shorebirdTokenEnvVar] = const CiToken(
          refreshToken: 'google-refresh-token',
          authProvider: AuthProvider.google,
        ).toBase64();
        final auth = buildAuth();

        await expectLater(
          auth.listApiKeys(),
          throwsA(isA<ApiKeySessionRequiredException>()),
        );
        verifyNever(() => httpClient.send(any()));
      });
    });

    group('listApiKeys', () {
      setUp(writeCredentials);

      test('sends a GET authenticated with the refresh token', () async {
        final requests = stubSend(body: jsonEncode({'api_keys': <dynamic>[]}));

        await buildAuth().listApiKeys();

        final request = requests.single;
        expect(request.method, equals('GET'));
        expect(
          request.url,
          equals(Uri.parse('https://auth.shorebird.dev/api/api-keys')),
        );
        expect(
          request.headers['Authorization'],
          equals('Bearer $refreshToken'),
        );
      });

      test('parses the returned keys', () async {
        stubSend(
          body: jsonEncode({
            'api_keys': [
              {
                'id': '7',
                'name': 'Production CI',
                'created_at': '2026-01-04T00:00:00.000Z',
                'last_used_at': null,
                'expires_at': null,
                'scope': 'release_and_patch',
              },
            ],
          }),
        );

        final keys = await buildAuth().listApiKeys();

        expect(keys, hasLength(1));
        expect(keys.single.id, equals('7'));
        expect(keys.single.scope, equals(ApiKeyScope.releaseAndPatch));
      });

      test('treats a missing api_keys field as empty', () async {
        stubSend(body: jsonEncode(<String, dynamic>{}));

        expect(await buildAuth().listApiKeys(), isEmpty);
      });

      test('surfaces the error_description from a failure', () async {
        stubSend(
          body: jsonEncode({
            'error': 'unauthorized',
            'error_description': 'Session expired',
          }),
          statusCode: HttpStatus.unauthorized,
        );

        await expectLater(
          buildAuth().listApiKeys(),
          throwsA(
            isA<ApiKeyRequestException>().having(
              (e) => e.message,
              'message',
              'Session expired',
            ),
          ),
        );
      });

      test('falls back to the status code for a non-JSON failure', () async {
        stubSend(body: '<html>gateway</html>', statusCode: 502);

        await expectLater(
          buildAuth().listApiKeys(),
          throwsA(
            isA<ApiKeyRequestException>().having(
              (e) => e.message,
              'message',
              contains('502'),
            ),
          ),
        );
      });

      test('wraps a transport failure', () async {
        when(
          () => httpClient.send(any()),
        ).thenThrow(const SocketException('offline'));

        await expectLater(
          buildAuth().listApiKeys(),
          throwsA(
            isA<ApiKeyRequestException>().having(
              (e) => e.message,
              'message',
              contains('Failed to reach the auth service'),
            ),
          ),
        );
      });
    });

    group('createApiKey', () {
      setUp(writeCredentials);

      test('posts the requested name, scope and expiry', () async {
        final requests = stubSend(
          body: jsonEncode({
            'api_key': 'sb_api_new',
            'id': '7',
            'name': 'Production CI',
            'created_at': '2026-01-04T00:00:00.000Z',
            'scope': 'release_and_patch',
          }),
        );

        final created = await buildAuth().createApiKey(
          name: 'Production CI',
          scope: ApiKeyScope.releaseAndPatch,
          expiresInDays: 90,
        );

        final request = requests.single as http.Request;
        expect(request.method, equals('POST'));
        expect(
          json.decode(request.body),
          equals({
            'name': 'Production CI',
            'scope': 'release_and_patch',
            'expires_in_days': 90,
          }),
        );
        expect(created.secret, equals('sb_api_new'));
        expect(created.metadata.id, equals('7'));
      });

      test('omits expires_in_days when it was not requested', () async {
        final requests = stubSend(
          body: jsonEncode({
            'api_key': 'sb_api_new',
            'id': '7',
            'name': 'Forever',
            'created_at': '2026-01-04T00:00:00.000Z',
            'scope': 'full_access',
          }),
        );

        await buildAuth().createApiKey(
          name: 'Forever',
          scope: ApiKeyScope.fullAccess,
        );

        final body =
            json.decode((requests.single as http.Request).body)
                as Map<String, dynamic>;
        expect(body.containsKey('expires_in_days'), isFalse);
      });

      test('throws when the server granted a wider scope', () async {
        stubSend(
          body: jsonEncode({
            'api_key': 'sb_api_new',
            'id': '7',
            'name': 'Production CI',
            'created_at': '2026-01-04T00:00:00.000Z',
            'scope': 'full_access',
          }),
        );

        await expectLater(
          buildAuth().createApiKey(
            name: 'Production CI',
            scope: ApiKeyScope.releaseAndPatch,
          ),
          throwsA(
            isA<ApiKeyScopeMismatchException>()
                .having(
                  (e) => e.requested,
                  'requested',
                  ApiKeyScope.releaseAndPatch,
                )
                .having((e) => e.granted, 'granted', ApiKeyScope.fullAccess),
          ),
        );
      });

      test('throws when the server reports no scope at all', () async {
        stubSend(
          body: jsonEncode({
            'api_key': 'sb_api_new',
            'id': '7',
            'name': 'Production CI',
            'created_at': '2026-01-04T00:00:00.000Z',
          }),
        );

        await expectLater(
          buildAuth().createApiKey(
            name: 'Production CI',
            scope: ApiKeyScope.releaseAndPatch,
          ),
          throwsA(isA<ApiKeyScopeMismatchException>()),
        );
      });
    });

    group('revokeApiKey', () {
      setUp(writeCredentials);

      test('sends a DELETE carrying the id', () async {
        final requests = stubSend(
          body: jsonEncode({'revoked': true}),
        );

        await buildAuth().revokeApiKey(id: '7');

        final request = requests.single as http.Request;
        expect(request.method, equals('DELETE'));
        expect(json.decode(request.body), equals({'id': '7'}));
      });

      test('throws when the key does not exist', () async {
        stubSend(
          body: jsonEncode({
            'error': 'not_found',
            'error_description': 'No such key',
          }),
          statusCode: HttpStatus.notFound,
        );

        await expectLater(
          buildAuth().revokeApiKey(id: '7'),
          throwsA(isA<ApiKeyRequestException>()),
        );
      });
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart' as oauth2;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/shorebird_oauth.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import '../mocks.dart';

class MockHttpClient extends Mock implements http.Client {}

/// Builds a JWT string with the given [issuer] for testing.
///
/// The token has a valid 3-part structure (header.payload.signature) that
/// can be parsed by `Jwt.parse()`.
String _buildTestJwt({String issuer = 'https://auth.shorebird.dev'}) {
  String b64(Map<String, dynamic> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

  final header = b64({'alg': 'RS256', 'kid': '1234', 'typ': 'JWT'});
  final payload = b64({
    'iss': issuer,
    'aud': 'shorebird',
    'sub': '12345',
    'email': 'test@email.com',
    'iat': 1234,
    'exp': 6789,
  });
  return '$header.$payload.dGVzdA';
}

/// The auth service's redirect back to [continueUrl]: [params] appended to the
/// callback URL, keeping the `state` the CLI put on it.
Uri _redirectTo(String continueUrl, Map<String, String> params) {
  final uri = Uri.parse(continueUrl);
  return uri.replace(queryParameters: {...uri.queryParameters, ...params});
}

void main() {
  late ShorebirdEnv shorebirdEnv;

  setUpAll(() {
    registerFallbackValue(Uri.parse(''));
  });

  setUp(() {
    shorebirdEnv = MockShorebirdEnv();
    when(
      () => shorebirdEnv.jwtIssuer,
    ).thenReturn('https://auth.shorebird.dev');
  });

  R runWithOverrides<R>(R Function() body) {
    return runScoped(
      body,
      values: {shorebirdEnvRef.overrideWith(() => shorebirdEnv)},
    );
  }

  group('obtainCredentialsViaLoopbackLogin', () {
    late MockHttpClient httpClient;
    final authBaseUrl = Uri.parse('https://auth.shorebird.dev');

    setUp(() {
      httpClient = MockHttpClient();
    });

    test('returns credentials on happy path', () async {
      final testJwt = _buildTestJwt();
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': testJwt,
            'refresh_token': 'sb_rt_test',
            'token_type': 'Bearer',
            'expires_in': 900,
          }),
          HttpStatus.ok,
        ),
      );

      late Uri loginUri;
      final credentials = await runWithOverrides(
        () => obtainCredentialsViaLoopbackLogin(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            // Simulate the browser redirect with an auth code.
            unawaited(
              http.get(_redirectTo(continueUrl, {'code': 'test_code'})),
            );
          },
        ),
      );

      expect(credentials.accessToken.type, equals('Bearer'));
      expect(credentials.accessToken.data, equals(testJwt));
      expect(credentials.refreshToken, equals('sb_rt_test'));
      expect(credentials.idToken, isNull);
      expect(credentials.scopes, isEmpty);

      final captured = verify(
        () => httpClient.post(
          captureAny(),
          headers: any(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      final tokenUrl = captured[0] as Uri;
      expect(tokenUrl.path, contains('/token'));
      final body = captured[1] as Map<String, String>;
      expect(body['grant_type'], equals('authorization_code'));
      expect(body['code'], equals('test_code'));
      // The verifier sent to /token is the one the login URL's challenge
      // was derived from.
      final codeVerifier = body['code_verifier']!;
      expect(codeVerifier, hasLength(43));
      expect(
        loginUri.queryParameters['code_challenge'],
        equals(codeChallengeFor(codeVerifier)),
      );
      expect(
        loginUri.queryParameters['code_challenge_method'],
        equals('S256'),
      );
    });

    test('constructs correct login URL with continue parameter', () async {
      final testJwt = _buildTestJwt();
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': testJwt,
            'refresh_token': 'rt',
            'token_type': 'Bearer',
            'expires_in': 900,
          }),
          HttpStatus.ok,
        ),
      );

      late String capturedUrl;
      await runWithOverrides(
        () => obtainCredentialsViaLoopbackLogin(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            capturedUrl = url;
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            unawaited(
              http.get(_redirectTo(continueUrl, {'code': 'test_code'})),
            );
          },
        ),
      );

      final loginUri = Uri.parse(capturedUrl);
      expect(loginUri.host, equals('auth.shorebird.dev'));
      expect(loginUri.path, contains('/login'));
      expect(
        loginUri.queryParameters['continue'],
        allOf(
          startsWith('http://localhost:'),
          contains('/callback'),
        ),
      );
      final continueUri = Uri.parse(loginUri.queryParameters['continue']!);
      expect(continueUri.queryParameters['state'], hasLength(43));
    });

    test('handles authBaseUrl with trailing slash', () async {
      final authBaseUrlWithSlash = Uri.parse('https://auth.shorebird.dev/v1/');
      final testJwt = _buildTestJwt(issuer: 'https://auth.shorebird.dev/v1/');
      when(
        () => shorebirdEnv.jwtIssuer,
      ).thenReturn('https://auth.shorebird.dev/v1/');

      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': testJwt,
            'refresh_token': 'rt',
            'token_type': 'Bearer',
            'expires_in': 900,
          }),
          HttpStatus.ok,
        ),
      );

      late String capturedUrl;
      await runWithOverrides(
        () => obtainCredentialsViaLoopbackLogin(
          httpClient: httpClient,
          authBaseUrl: authBaseUrlWithSlash,
          userPrompt: (url) {
            capturedUrl = url;
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            unawaited(
              http.get(_redirectTo(continueUrl, {'code': 'test_code'})),
            );
          },
        ),
      );

      final loginUri = Uri.parse(capturedUrl);
      expect(loginUri.path, equals('/v1/login'));

      final captured = verify(
        () => httpClient.post(
          captureAny(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).captured;
      final tokenUrl = captured[0] as Uri;
      expect(tokenUrl.path, equals('/v1/token'));
    });

    test('ignores non-callback requests like favicon', () async {
      final testJwt = _buildTestJwt();
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': testJwt,
            'refresh_token': 'sb_rt_test',
            'token_type': 'Bearer',
            'expires_in': 900,
          }),
          HttpStatus.ok,
        ),
      );

      final credentials = await runWithOverrides(
        () => obtainCredentialsViaLoopbackLogin(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            final callbackUri = Uri.parse(continueUrl);
            final baseUrl = 'http://localhost:${callbackUri.port}';
            // Send a favicon request first — should be ignored.
            // Use .ignore() because the server may close before responding.
            http.get(Uri.parse('$baseUrl/favicon.ico')).ignore();
            // Then send the actual callback with auth code.
            unawaited(
              http.get(_redirectTo(continueUrl, {'code': 'test_code'})),
            );
          },
        ),
      );

      expect(credentials.accessToken.type, equals('Bearer'));
      expect(credentials.refreshToken, equals('sb_rt_test'));
    });

    test('throws when redirect contains error parameter', () async {
      await expectLater(
        obtainCredentialsViaLoopbackLogin(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            unawaited(
              http.get(
                _redirectTo(continueUrl, {'error': 'invalid_redirect'}),
              ),
            );
          },
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('invalid_redirect'),
          ),
        ),
      );
    });

    for (final (description, state) in [
      ('does not match', 'not-the-state'),
      ('is missing', null),
    ]) {
      test('throws when the callback state $description', () async {
        await expectLater(
          obtainCredentialsViaLoopbackLogin(
            httpClient: httpClient,
            authBaseUrl: authBaseUrl,
            userPrompt: (url) {
              final loginUri = Uri.parse(url);
              final callbackUri = Uri.parse(
                loginUri.queryParameters['continue']!,
              );
              unawaited(
                http.get(
                  callbackUri.replace(
                    queryParameters: {
                      'code': 'test_code',
                      'state': ?state,
                    },
                  ),
                ),
              );
            },
          ),
          throwsA(
            isA<ShorebirdAuthException>().having(
              (e) => e.message,
              'message',
              contains('did not match this login request'),
            ),
          ),
        );
        verifyNever(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        );
      });
    }

    test('two logins use different state and verifiers', () async {
      final loginUris = <Uri>[];
      for (var i = 0; i < 2; i++) {
        await expectLater(
          obtainCredentialsViaLoopbackLogin(
            httpClient: httpClient,
            authBaseUrl: authBaseUrl,
            userPrompt: (url) {
              loginUris.add(Uri.parse(url));
              unawaited(
                http.get(
                  _redirectTo(Uri.parse(url).queryParameters['continue']!, {
                    'error': 'access_denied',
                  }),
                ),
              );
            },
          ),
          throwsA(isA<ShorebirdAuthException>()),
        );
      }
      expect(
        loginUris[0].queryParameters['continue'],
        isNot(equals(loginUris[1].queryParameters['continue'])),
      );
      expect(
        loginUris[0].queryParameters['code_challenge'],
        isNot(equals(loginUris[1].queryParameters['code_challenge'])),
      );
    });

    test('throws when redirect has no code parameter', () async {
      await expectLater(
        obtainCredentialsViaLoopbackLogin(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            unawaited(
              http.get(Uri.parse(continueUrl)),
            );
          },
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('no auth code received'),
          ),
        ),
      );
    });

    test('throws when token exchange returns non-200', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response('Unauthorized', HttpStatus.unauthorized),
      );

      await expectLater(
        obtainCredentialsViaLoopbackLogin(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            // Use .ignore() to suppress connection errors when the server
            // closes after the token exchange failure.
            http.get(_redirectTo(continueUrl, {'code': 'test_code'})).ignore();
          },
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('Token exchange failed (401)'),
          ),
        ),
      );
    });

    test('throws on timeout when no redirect arrives', () async {
      await expectLater(
        obtainCredentialsViaLoopbackLogin(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (_) {
            // Do nothing — simulate the browser never redirecting.
          },
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('Timed out'),
          ),
        ),
      );
    });

    test('throws when access_token is not a valid JWT', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': 'not_a_jwt',
            'refresh_token': 'sb_rt_test',
            'token_type': 'Bearer',
            'expires_in': 900,
          }),
          HttpStatus.ok,
        ),
      );

      await expectLater(
        runWithOverrides(
          () => obtainCredentialsViaLoopbackLogin(
            httpClient: httpClient,
            authBaseUrl: authBaseUrl,
            userPrompt: (url) {
              final loginUri = Uri.parse(url);
              final continueUrl = loginUri.queryParameters['continue']!;
              http
                  .get(_redirectTo(continueUrl, {'code': 'test_code'}))
                  .ignore();
            },
          ),
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('Invalid access token'),
          ),
        ),
      );
    });

    test('throws when JWT issuer does not match expected issuer', () async {
      final wrongIssuerJwt = _buildTestJwt(issuer: 'https://evil.example.com');
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': wrongIssuerJwt,
            'refresh_token': 'sb_rt_test',
            'token_type': 'Bearer',
            'expires_in': 900,
          }),
          HttpStatus.ok,
        ),
      );

      await expectLater(
        runWithOverrides(
          () => obtainCredentialsViaLoopbackLogin(
            httpClient: httpClient,
            authBaseUrl: authBaseUrl,
            userPrompt: (url) {
              final loginUri = Uri.parse(url);
              final continueUrl = loginUri.queryParameters['continue']!;
              http
                  .get(_redirectTo(continueUrl, {'code': 'test_code'}))
                  .ignore();
            },
          ),
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('Token issuer mismatch'),
          ),
        ),
      );
    });

    test('throws on network error during token exchange', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenThrow(
        const SocketException('Connection refused'),
      );

      await expectLater(
        obtainCredentialsViaLoopbackLogin(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            http.get(_redirectTo(continueUrl, {'code': 'test_code'})).ignore();
          },
        ),
        throwsA(isA<SocketException>()),
      );
    });

    test('throws when response body is not valid JSON', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '<html>Server Error</html>',
          HttpStatus.ok,
        ),
      );

      await expectLater(
        runWithOverrides(
          () => obtainCredentialsViaLoopbackLogin(
            httpClient: httpClient,
            authBaseUrl: authBaseUrl,
            userPrompt: (url) {
              final loginUri = Uri.parse(url);
              final continueUrl = loginUri.queryParameters['continue']!;
              http
                  .get(_redirectTo(continueUrl, {'code': 'test_code'}))
                  .ignore();
            },
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when response is missing access_token', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'refresh_token': 'sb_rt_test',
            'token_type': 'Bearer',
            'expires_in': 900,
          }),
          HttpStatus.ok,
        ),
      );

      await expectLater(
        runWithOverrides(
          () => obtainCredentialsViaLoopbackLogin(
            httpClient: httpClient,
            authBaseUrl: authBaseUrl,
            userPrompt: (url) {
              final loginUri = Uri.parse(url);
              final continueUrl = loginUri.queryParameters['continue']!;
              http
                  .get(_redirectTo(continueUrl, {'code': 'test_code'}))
                  .ignore();
            },
          ),
        ),
        throwsA(isA<TypeError>()),
      );
    });

    test('throws when response is missing expires_in', () async {
      final testJwt = _buildTestJwt();
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': testJwt,
            'refresh_token': 'sb_rt_test',
            'token_type': 'Bearer',
          }),
          HttpStatus.ok,
        ),
      );

      await expectLater(
        runWithOverrides(
          () => obtainCredentialsViaLoopbackLogin(
            httpClient: httpClient,
            authBaseUrl: authBaseUrl,
            userPrompt: (url) {
              final loginUri = Uri.parse(url);
              final continueUrl = loginUri.queryParameters['continue']!;
              http
                  .get(_redirectTo(continueUrl, {'code': 'test_code'}))
                  .ignore();
            },
          ),
        ),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('refreshShorebirdCredentials', () {
    late MockHttpClient httpClient;
    final authBaseUrl = Uri.parse('https://auth.shorebird.dev');

    setUp(() {
      httpClient = MockHttpClient();
    });

    test('returns new credentials with rotated refresh token', () async {
      final testJwt = _buildTestJwt();
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': testJwt,
            'refresh_token': 'sb_rt_new',
            'token_type': 'Bearer',
            'expires_in': 900,
          }),
          HttpStatus.ok,
        ),
      );

      final credentials = await runWithOverrides(
        () => refreshShorebirdCredentials(
          oauth2.AccessCredentials(
            AccessToken('Bearer', '', DateTime.timestamp()),
            'sb_rt_old',
            [],
          ),
          httpClient,
          authBaseUrl: authBaseUrl,
        ),
      );

      expect(credentials.accessToken.type, equals('Bearer'));
      expect(credentials.accessToken.data, equals(testJwt));
      expect(credentials.refreshToken, equals('sb_rt_new'));
      expect(credentials.idToken, isNull);
      expect(credentials.scopes, isEmpty);

      final captured = verify(
        () => httpClient.post(
          captureAny(),
          headers: any(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      final tokenUrl = captured[0] as Uri;
      expect(tokenUrl.path, contains('/token'));
      final body = captured[1] as Map<String, String>;
      expect(body['grant_type'], equals('refresh_token'));
      expect(body['refresh_token'], equals('sb_rt_old'));
    });

    test('throws when no refresh token is available', () async {
      await expectLater(
        refreshShorebirdCredentials(
          oauth2.AccessCredentials(
            AccessToken('Bearer', '', DateTime.timestamp()),
            null,
            [],
          ),
          httpClient,
          authBaseUrl: authBaseUrl,
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('No refresh token available'),
          ),
        ),
      );
    });

    test('throws when token refresh returns 401', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          'Token expired',
          HttpStatus.unauthorized,
        ),
      );

      await expectLater(
        refreshShorebirdCredentials(
          oauth2.AccessCredentials(
            AccessToken('Bearer', '', DateTime.timestamp()),
            'sb_rt_expired',
            [],
          ),
          httpClient,
          authBaseUrl: authBaseUrl,
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('Token refresh failed (401)'),
          ),
        ),
      );
    });

    test('throws with message on network error', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenThrow(
        const SocketException('Connection refused'),
      );

      await expectLater(
        refreshShorebirdCredentials(
          oauth2.AccessCredentials(
            AccessToken('Bearer', '', DateTime.timestamp()),
            'sb_rt_test',
            [],
          ),
          httpClient,
          authBaseUrl: authBaseUrl,
        ),
        throwsA(isA<SocketException>()),
      );
    });

    test('throws when access_token is not a valid JWT', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': 'not_a_jwt',
            'refresh_token': 'sb_rt_new',
            'token_type': 'Bearer',
            'expires_in': 900,
          }),
          HttpStatus.ok,
        ),
      );

      await expectLater(
        runWithOverrides(
          () => refreshShorebirdCredentials(
            oauth2.AccessCredentials(
              AccessToken('Bearer', '', DateTime.timestamp()),
              'sb_rt_old',
              [],
            ),
            httpClient,
            authBaseUrl: authBaseUrl,
          ),
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('Invalid access token'),
          ),
        ),
      );
    });

    test('throws when JWT issuer does not match expected issuer', () async {
      final wrongIssuerJwt = _buildTestJwt(issuer: 'https://evil.example.com');
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': wrongIssuerJwt,
            'refresh_token': 'sb_rt_new',
            'token_type': 'Bearer',
            'expires_in': 900,
          }),
          HttpStatus.ok,
        ),
      );

      await expectLater(
        runWithOverrides(
          () => refreshShorebirdCredentials(
            oauth2.AccessCredentials(
              AccessToken('Bearer', '', DateTime.timestamp()),
              'sb_rt_old',
              [],
            ),
            httpClient,
            authBaseUrl: authBaseUrl,
          ),
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('Token issuer mismatch'),
          ),
        ),
      );
    });

    test('throws when response body is not valid JSON', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '<html>Server Error</html>',
          HttpStatus.ok,
        ),
      );

      await expectLater(
        runWithOverrides(
          () => refreshShorebirdCredentials(
            oauth2.AccessCredentials(
              AccessToken('Bearer', '', DateTime.timestamp()),
              'sb_rt_old',
              [],
            ),
            httpClient,
            authBaseUrl: authBaseUrl,
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when response is missing access_token', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'refresh_token': 'sb_rt_new',
            'token_type': 'Bearer',
            'expires_in': 900,
          }),
          HttpStatus.ok,
        ),
      );

      await expectLater(
        runWithOverrides(
          () => refreshShorebirdCredentials(
            oauth2.AccessCredentials(
              AccessToken('Bearer', '', DateTime.timestamp()),
              'sb_rt_old',
              [],
            ),
            httpClient,
            authBaseUrl: authBaseUrl,
          ),
        ),
        throwsA(isA<TypeError>()),
      );
    });

    test('throws when response is missing expires_in', () async {
      final testJwt = _buildTestJwt();
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': testJwt,
            'refresh_token': 'sb_rt_new',
            'token_type': 'Bearer',
          }),
          HttpStatus.ok,
        ),
      );

      await expectLater(
        runWithOverrides(
          () => refreshShorebirdCredentials(
            oauth2.AccessCredentials(
              AccessToken('Bearer', '', DateTime.timestamp()),
              'sb_rt_old',
              [],
            ),
            httpClient,
            authBaseUrl: authBaseUrl,
          ),
        ),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('codeChallengeFor', () {
    test('matches the RFC 7636 appendix B example', () {
      expect(
        codeChallengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        equals('E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'),
      );
    });
  });

  group('ShorebirdAuthException', () {
    test('toString includes message', () {
      const exception = ShorebirdAuthException('test error');
      expect(
        exception.toString(),
        equals('ShorebirdAuthException: test error'),
      );
    });
  });
}

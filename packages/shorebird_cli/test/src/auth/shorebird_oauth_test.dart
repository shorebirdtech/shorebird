import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart' as oauth2;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/shorebird_oauth.dart';
import 'package:test/test.dart';

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

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse(''));
  });

  group('obtainShorebirdCredentials', () {
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

      final credentials = await obtainShorebirdCredentials(
        httpClient: httpClient,
        authBaseUrl: authBaseUrl,
        userPrompt: (url) {
          final loginUri = Uri.parse(url);
          final continueUrl = loginUri.queryParameters['continue']!;
          // Simulate the browser redirect with an auth code.
          unawaited(
            http.get(Uri.parse('$continueUrl?code=test_code')),
          );
        },
      );

      expect(credentials.accessToken.type, equals('Bearer'));
      expect(credentials.accessToken.data, equals(testJwt));
      expect(credentials.refreshToken, equals('sb_rt_test'));
      expect(credentials.idToken, equals(testJwt));
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
      final body = captured[1] as String;
      expect(body, contains('grant_type=authorization_code'));
      expect(body, contains('code=test_code'));
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
      await obtainShorebirdCredentials(
        httpClient: httpClient,
        authBaseUrl: authBaseUrl,
        userPrompt: (url) {
          capturedUrl = url;
          final loginUri = Uri.parse(url);
          final continueUrl = loginUri.queryParameters['continue']!;
          unawaited(
            http.get(Uri.parse('$continueUrl?code=test_code')),
          );
        },
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
    });

    test('handles authBaseUrl with trailing slash', () async {
      final authBaseUrlWithSlash = Uri.parse('https://auth.shorebird.dev/v1/');
      final testJwt = _buildTestJwt(issuer: 'https://auth.shorebird.dev/v1/');

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
      await obtainShorebirdCredentials(
        httpClient: httpClient,
        authBaseUrl: authBaseUrlWithSlash,
        userPrompt: (url) {
          capturedUrl = url;
          final loginUri = Uri.parse(url);
          final continueUrl = loginUri.queryParameters['continue']!;
          unawaited(
            http.get(Uri.parse('$continueUrl?code=test_code')),
          );
        },
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

      final credentials = await obtainShorebirdCredentials(
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
            http.get(Uri.parse('$continueUrl?code=test_code')),
          );
        },
      );

      expect(credentials.accessToken.type, equals('Bearer'));
      expect(credentials.refreshToken, equals('sb_rt_test'));
    });

    test('throws when redirect contains error parameter', () async {
      await expectLater(
        obtainShorebirdCredentials(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            unawaited(
              http.get(
                Uri.parse('$continueUrl?error=invalid_redirect'),
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

    test('throws when redirect has no code parameter', () async {
      await expectLater(
        obtainShorebirdCredentials(
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
        obtainShorebirdCredentials(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            // Use .ignore() to suppress connection errors when the server
            // closes after the token exchange failure.
            http.get(Uri.parse('$continueUrl?code=test_code')).ignore();
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
        obtainShorebirdCredentials(
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
        obtainShorebirdCredentials(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            http.get(Uri.parse('$continueUrl?code=test_code')).ignore();
          },
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
        obtainShorebirdCredentials(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            http.get(Uri.parse('$continueUrl?code=test_code')).ignore();
          },
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

    test(
      'succeeds when JWT issuer has trailing slash but authBaseUrl does not',
      () async {
        // JWT has trailing slash, authBaseUrl does not.
        final jwt = _buildTestJwt(issuer: 'https://auth.shorebird.dev/');
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'access_token': jwt,
              'refresh_token': 'sb_rt_test',
              'token_type': 'Bearer',
              'expires_in': 900,
            }),
            HttpStatus.ok,
          ),
        );

        final credentials = await obtainShorebirdCredentials(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl, // https://auth.shorebird.dev (no slash)
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            http.get(Uri.parse('$continueUrl?code=test_code')).ignore();
          },
        );

        expect(credentials.accessToken.type, equals('Bearer'));
      },
    );

    test(
      'succeeds when authBaseUrl has trailing slash but JWT issuer does not',
      () async {
        // JWT has no trailing slash, authBaseUrl does.
        final jwt = _buildTestJwt(issuer: 'https://auth.shorebird.dev');
        final authBaseUrlWithSlash = Uri.parse('https://auth.shorebird.dev/');
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'access_token': jwt,
              'refresh_token': 'sb_rt_test',
              'token_type': 'Bearer',
              'expires_in': 900,
            }),
            HttpStatus.ok,
          ),
        );

        final credentials = await obtainShorebirdCredentials(
          httpClient: httpClient,
          authBaseUrl: authBaseUrlWithSlash,
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            http.get(Uri.parse('$continueUrl?code=test_code')).ignore();
          },
        );

        expect(credentials.accessToken.type, equals('Bearer'));
      },
    );

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
        obtainShorebirdCredentials(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            http.get(Uri.parse('$continueUrl?code=test_code')).ignore();
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
        obtainShorebirdCredentials(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            http.get(Uri.parse('$continueUrl?code=test_code')).ignore();
          },
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
        obtainShorebirdCredentials(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            http.get(Uri.parse('$continueUrl?code=test_code')).ignore();
          },
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
        obtainShorebirdCredentials(
          httpClient: httpClient,
          authBaseUrl: authBaseUrl,
          userPrompt: (url) {
            final loginUri = Uri.parse(url);
            final continueUrl = loginUri.queryParameters['continue']!;
            http.get(Uri.parse('$continueUrl?code=test_code')).ignore();
          },
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

      final credentials = await refreshShorebirdCredentials(
        oauth2.AccessCredentials(
          AccessToken('Bearer', '', DateTime.timestamp()),
          'sb_rt_old',
          [],
        ),
        httpClient,
        authBaseUrl: authBaseUrl,
      );

      expect(credentials.accessToken.type, equals('Bearer'));
      expect(credentials.accessToken.data, equals(testJwt));
      expect(credentials.refreshToken, equals('sb_rt_new'));
      expect(credentials.idToken, equals(testJwt));
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
      final body = captured[1] as String;
      expect(body, contains('grant_type=refresh_token'));
      expect(body, contains('refresh_token=sb_rt_old'));
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
        refreshShorebirdCredentials(
          oauth2.AccessCredentials(
            AccessToken('Bearer', '', DateTime.timestamp()),
            'sb_rt_old',
            [],
          ),
          httpClient,
          authBaseUrl: authBaseUrl,
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
        refreshShorebirdCredentials(
          oauth2.AccessCredentials(
            AccessToken('Bearer', '', DateTime.timestamp()),
            'sb_rt_old',
            [],
          ),
          httpClient,
          authBaseUrl: authBaseUrl,
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
        refreshShorebirdCredentials(
          oauth2.AccessCredentials(
            AccessToken('Bearer', '', DateTime.timestamp()),
            'sb_rt_old',
            [],
          ),
          httpClient,
          authBaseUrl: authBaseUrl,
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
        refreshShorebirdCredentials(
          oauth2.AccessCredentials(
            AccessToken('Bearer', '', DateTime.timestamp()),
            'sb_rt_old',
            [],
          ),
          httpClient,
          authBaseUrl: authBaseUrl,
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
        refreshShorebirdCredentials(
          oauth2.AccessCredentials(
            AccessToken('Bearer', '', DateTime.timestamp()),
            'sb_rt_old',
            [],
          ),
          httpClient,
          authBaseUrl: authBaseUrl,
        ),
        throwsA(isA<TypeError>()),
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

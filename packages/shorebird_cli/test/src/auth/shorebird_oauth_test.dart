import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:shorebird_cli/src/auth/shorebird_oauth.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

/// An access token, which is opaque to the CLI.
const _testAccessToken = 'sb_at_test';

/// A JSON response, as the auth service sends every answer from `/token`.
http.Response _json(Object body, {int status = HttpStatus.ok}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// The auth service's redirect back to the `redirect_uri` of [loginUri],
/// carrying [params] and the `state` the login sent.
Uri _redirectTo(Uri loginUri, Map<String, String> params) {
  return _redirectUri(loginUri).replace(
    queryParameters: {'state': loginUri.queryParameters['state'], ...params},
  );
}

/// Sends the browser's GET to [uri] without following the redirect the CLI
/// answers with, so a test never leaves the loopback server.
Future<http.Response> _getWithoutFollowing(Uri uri) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', uri)..followRedirects = false;
    return await http.Response.fromStream(await client.send(request));
  } finally {
    client.close();
  }
}

/// The `redirect_uri` the authorization request at [loginUri] names.
Uri _redirectUri(Uri loginUri) =>
    Uri.parse(loginUri.queryParameters['redirect_uri']!);

/// The S256 PKCE code challenge for [codeVerifier] (RFC 7636 section 4.2).
String _codeChallengeFor(String codeVerifier) => base64Url
    .encode(sha256.convert(ascii.encode(codeVerifier)).bytes)
    .replaceAll('=', '');

void main() {
  useTempWorkingDirectory();

  setUpAll(() {
    registerFallbackValue(Uri.parse(''));
  });

  group('obtainCredentialsViaLoopbackLogin', () {
    late MockHttpClient httpClient;
    final authBaseUrl = Uri.parse('https://auth.shorebird.dev');
    final tokenJson = {
      'access_token': _testAccessToken,
      'refresh_token': 'sb_rt_test',
      'token_type': 'Bearer',
      'expires_in': 900,
    };

    void answerTokenRequestsWith(http.Response response) {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => response);
    }

    void verifyNoTokenRequest() => verifyNever(
      () => httpClient.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    );

    /// Logs in, with the browser following the auth service's redirect to
    /// the callback with [params] once the CLI prompts with the login URL.
    ///
    /// Completes [browserPage] with the CLI's answer to the browser.
    Future<oauth2.Credentials> loginRedirectingWith(
      Map<String, String> params, {
      Uri? authBaseUrlOverride,
      void Function(Uri loginUri)? onPrompt,
      Completer<http.Response>? browserPage,
    }) {
      return obtainCredentialsViaLoopbackLogin(
        httpClient: httpClient,
        authBaseUrl: authBaseUrlOverride ?? authBaseUrl,
        userPrompt: (url) {
          final loginUri = Uri.parse(url);
          onPrompt?.call(loginUri);
          final page = _getWithoutFollowing(_redirectTo(loginUri, params));
          if (browserPage != null) {
            unawaited(page.then(browserPage.complete));
          } else {
            page.ignore();
          }
        },
      );
    }

    /// Expects [response] to send the browser to the auth service's login
    /// result page for [status].
    void expectLoginResultPage(
      http.Response response, {
      required String status,
    }) {
      expect(response.statusCode, equals(HttpStatus.seeOther));
      expect(
        response.headers['location'],
        equals('$authBaseUrl/cli/login-result?status=$status'),
      );
    }

    setUp(() {
      httpClient = MockHttpClient();
    });

    test('returns credentials on happy path', () async {
      answerTokenRequestsWith(_json(tokenJson));

      late Uri loginUri;
      final before = DateTime.now();
      final browserPage = Completer<http.Response>();
      final credentials = await loginRedirectingWith(
        {'code': 'test_code'},
        onPrompt: (uri) => loginUri = uri,
        browserPage: browserPage,
      );

      expect(credentials.accessToken, equals(_testAccessToken));
      expect(credentials.refreshToken, equals('sb_rt_test'));
      expect(credentials.idToken, isNull);
      expect(credentials.scopes, equals(['api']));
      expect(
        credentials.tokenEndpoint,
        equals(Uri.parse('https://auth.shorebird.dev/token')),
      );
      expect(
        credentials.expiration!.isAfter(
          before.add(const Duration(minutes: 14)),
        ),
        isTrue,
      );
      expectLoginResultPage(await browserPage.future, status: 'success');

      final captured = verify(
        () => httpClient.post(
          captureAny(),
          headers: any(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      expect(
        captured[0],
        equals(Uri.parse('https://auth.shorebird.dev/token')),
      );
      final body = captured[1] as Map<String, String?>;
      expect(body['grant_type'], equals('authorization_code'));
      expect(body['code'], equals('test_code'));
      expect(body['client_id'], equals('shorebird-cli'));
      // The exchange names the exact redirect URI the authorization request
      // sent (RFC 6749 section 4.1.3).
      expect(
        body['redirect_uri'],
        equals(loginUri.queryParameters['redirect_uri']),
      );
      // The verifier sent to /token is the one the login URL's challenge
      // was derived from.
      expect(
        loginUri.queryParameters['code_challenge'],
        equals(_codeChallengeFor(body['code_verifier']!)),
      );
    });

    test('sends a standard authorization request for shorebird-cli', () async {
      answerTokenRequestsWith(_json(tokenJson));

      late Uri loginUri;
      await loginRedirectingWith({
        'code': 'test_code',
      }, onPrompt: (uri) => loginUri = uri);

      expect(loginUri.host, equals('auth.shorebird.dev'));
      expect(loginUri.path, equals('/login'));
      expect(
        loginUri.queryParameters.keys,
        unorderedEquals([
          'response_type',
          'client_id',
          'redirect_uri',
          'scope',
          'state',
          'code_challenge',
          'code_challenge_method',
        ]),
      );
      expect(loginUri.queryParameters['response_type'], equals('code'));
      expect(loginUri.queryParameters['client_id'], equals('shorebird-cli'));
      expect(loginUri.queryParameters['scope'], equals('api'));
      expect(loginUri.queryParameters['state'], hasLength(43));
      expect(loginUri.queryParameters['code_challenge_method'], equals('S256'));
      // The registered loopback redirect, on whatever port the CLI bound, with
      // no query: the auth service compares path and query exactly.
      final redirectUri = _redirectUri(loginUri);
      expect(redirectUri.port, isNonZero);
      expect(
        redirectUri,
        equals(Uri.parse('http://localhost:${redirectUri.port}/callback')),
      );
    });

    test('handles authBaseUrl with a path and trailing slash', () async {
      answerTokenRequestsWith(_json(tokenJson));

      late Uri loginUri;
      final browserPage = Completer<http.Response>();
      final credentials = await loginRedirectingWith(
        {'code': 'test_code'},
        authBaseUrlOverride: Uri.parse('https://auth.shorebird.dev/v1/'),
        onPrompt: (uri) => loginUri = uri,
        browserPage: browserPage,
      );

      expect(loginUri.path, equals('/v1/login'));
      expect(
        (await browserPage.future).headers['location'],
        equals('https://auth.shorebird.dev/v1/cli/login-result?status=success'),
      );
      expect(
        credentials.tokenEndpoint,
        equals(Uri.parse('https://auth.shorebird.dev/v1/token')),
      );
    });

    test('ignores non-callback requests like favicon', () async {
      answerTokenRequestsWith(_json(tokenJson));

      final credentials = await obtainCredentialsViaLoopbackLogin(
        httpClient: httpClient,
        authBaseUrl: authBaseUrl,
        userPrompt: (url) {
          final loginUri = Uri.parse(url);
          final callbackUri = _redirectUri(loginUri);
          // Use .ignore() because the server may close before responding.
          _getWithoutFollowing(
            callbackUri.replace(path: '/favicon.ico', query: ''),
          ).ignore();
          unawaited(
            _getWithoutFollowing(_redirectTo(loginUri, {'code': 'test_code'})),
          );
        },
      );

      expect(credentials.refreshToken, equals('sb_rt_test'));
    });

    test('two logins use different state and verifiers', () async {
      final loginUris = <Uri>[];
      for (var i = 0; i < 2; i++) {
        await expectLater(
          loginRedirectingWith({
            'error': 'access_denied',
          }, onPrompt: loginUris.add),
          throwsA(isA<oauth2.AuthorizationException>()),
        );
      }
      expect(
        loginUris[0].queryParameters['state'],
        isNot(equals(loginUris[1].queryParameters['state'])),
      );
      expect(
        loginUris[0].queryParameters['code_challenge'],
        isNot(equals(loginUris[1].queryParameters['code_challenge'])),
      );
    });

    test('throws the error a callback carries', () async {
      final browserPage = Completer<http.Response>();
      await expectLater(
        loginRedirectingWith({
          'error': 'access_denied',
          'error_description': 'The user denied the request.',
        }, browserPage: browserPage),
        throwsA(
          isA<oauth2.AuthorizationException>()
              .having((e) => e.error, 'error', 'access_denied')
              .having(
                (e) => e.description,
                'description',
                'The user denied the request.',
              ),
        ),
      );
      expectLoginResultPage(await browserPage.future, status: 'failed');
      verifyNoTokenRequest();
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
              final callbackUri = _redirectUri(Uri.parse(url));
              _getWithoutFollowing(
                callbackUri.replace(
                  queryParameters: {'code': 'test_code', 'state': ?state},
                ),
              ).ignore();
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('parameter "state"'),
            ),
          ),
        );
        verifyNoTokenRequest();
      });
    }

    test('throws when the callback has no code', () async {
      await expectLater(
        loginRedirectingWith({}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('"code"'),
          ),
        ),
      );
      verifyNoTokenRequest();
    });

    test('throws the OAuth error of a refused exchange', () async {
      answerTokenRequestsWith(
        _json({
          'error': 'invalid_grant',
          'error_description': 'Code already used',
        }, status: HttpStatus.badRequest),
      );

      final browserPage = Completer<http.Response>();
      await expectLater(
        loginRedirectingWith({'code': 'test_code'}, browserPage: browserPage),
        throwsA(
          isA<oauth2.AuthorizationException>()
              .having((e) => e.error, 'error', 'invalid_grant')
              .having((e) => e.description, 'description', 'Code already used'),
        ),
      );
      expectLoginResultPage(await browserPage.future, status: 'failed');
    });

    test('throws when the exchange gets no OAuth answer', () async {
      answerTokenRequestsWith(http.Response('', HttpStatus.tooManyRequests));

      await expectLater(
        loginRedirectingWith({'code': 'test_code'}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('status 429'),
          ),
        ),
      );
    });

    test('throws when the token response is not JSON', () async {
      answerTokenRequestsWith(
        http.Response(
          '<html>Server Error</html>',
          HttpStatus.ok,
          headers: {'content-type': 'text/html'},
        ),
      );

      await expectLater(
        loginRedirectingWith({'code': 'test_code'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when the token response has no access_token', () async {
      answerTokenRequestsWith(_json({...tokenJson}..remove('access_token')));

      await expectLater(
        loginRedirectingWith({'code': 'test_code'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws on network error during token exchange', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenThrow(const SocketException('Connection refused'));

      await expectLater(
        loginRedirectingWith({'code': 'test_code'}),
        throwsA(isA<SocketException>()),
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
  });

  group('tokenEndpointFor', () {
    test('appends token to the auth base URL path', () {
      expect(
        tokenEndpointFor(Uri.parse('https://auth.shorebird.dev')),
        equals(Uri.parse('https://auth.shorebird.dev/token')),
      );
      expect(
        tokenEndpointFor(Uri.parse('https://example.com/auth/')),
        equals(Uri.parse('https://example.com/auth/token')),
      );
    });
  });

  group('revokeShorebirdRefreshToken', () {
    late MockHttpClient httpClient;

    setUp(() {
      httpClient = MockHttpClient();
    });

    test('posts the refresh token to the revocation endpoint', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('', HttpStatus.ok));

      await revokeShorebirdRefreshToken(
        'sb_rt_test',
        httpClient,
        authBaseUrl: Uri.parse('https://auth.shorebird.dev/base'),
      );

      final captured = verify(
        () => httpClient.post(
          captureAny(),
          headers: any(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      expect(
        captured[0],
        equals(Uri.parse('https://auth.shorebird.dev/base/revoke')),
      );
      expect(
        captured[1],
        equals({
          'token': 'sb_rt_test',
          'token_type_hint': 'refresh_token',
          'client_id': 'shorebird-cli',
        }),
      );
    });

    test('throws when the auth service does not answer 200', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '{"error":"invalid_client"}',
          HttpStatus.unauthorized,
        ),
      );

      await expectLater(
        revokeShorebirdRefreshToken(
          'sb_rt_test',
          httpClient,
          authBaseUrl: Uri.parse('https://auth.shorebird.dev'),
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('Token revocation failed (401)'),
          ),
        ),
      );
    });
  });

  group('ShorebirdAuthException', () {
    test('toString includes message', () {
      expect(
        const ShorebirdAuthException('boom').toString(),
        equals('ShorebirdAuthException: boom'),
      );
    });
  });
}

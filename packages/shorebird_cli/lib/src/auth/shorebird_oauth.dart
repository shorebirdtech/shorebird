import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:googleapis_auth/auth_io.dart' as oauth2;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:jwt/jwt.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/shorebird_env.dart';

/// Exception thrown when the Shorebird auth flow fails.
class ShorebirdAuthException implements Exception {
  /// Creates a [ShorebirdAuthException] with the given [message].
  const ShorebirdAuthException(this.message, {this.statusCode});

  /// The error message.
  final String message;

  /// The HTTP status the auth service answered with, where there was one.
  ///
  /// Null when the request never got an answer -- no network, DNS failure, a
  /// connection reset -- or when the failure is local, such as having no
  /// refresh token to send.
  final int? statusCode;

  /// Whether the auth service refused the credentials themselves, as opposed
  /// to failing to answer.
  ///
  /// Only a 4xx says anything about the credentials. A 5xx, or no answer at
  /// all, says the service is having a bad day; reading that as a rejection
  /// would log a user out because their wifi dropped.
  bool get isCredentialRejection {
    final status = statusCode;
    return status != null && status >= 400 && status < 500;
  }

  @override
  String toString() => 'ShorebirdAuthException: $message';
}

/// Implements the full loopback login flow for Shorebird auth, following
/// OAuth 2.0 for native apps (RFC 8252).
///
/// 1. Binds a local HTTP server on localhost with a random port.
/// 2. Generates a PKCE code verifier (RFC 7636) and a `state` value.
/// 3. Constructs the login URL pointing to the auth service, carrying the
///    S256 code challenge. `state` rides on the callback URL itself, which the
///    auth service redirects back to with the code appended.
/// 4. Calls [userPrompt] with the login URL.
/// 5. Waits for the auth service to redirect back with an auth code, and
///    rejects a callback whose `state` does not match.
/// 6. Exchanges the auth code and code verifier for tokens via the auth
///    service's /token endpoint.
/// 7. Returns the tokens as [oauth2.AccessCredentials].
Future<oauth2.AccessCredentials> obtainCredentialsViaLoopbackLogin({
  required http.Client httpClient,
  required Uri authBaseUrl,
  required void Function(String) userPrompt,
  Duration timeout = const Duration(minutes: 5),
}) async {
  HttpServer server;
  try {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  } on SocketException {
    server = await HttpServer.bind(InternetAddress.loopbackIPv6, 0);
  }
  try {
    final port = server.port;
    const callbackPath = '/callback';
    final state = _randomUrlSafeString();
    final codeVerifier = _randomUrlSafeString();
    final callbackUrl = Uri(
      scheme: 'http',
      host: 'localhost',
      port: port,
      path: callbackPath,
      queryParameters: {'state': state},
    );
    final loginUrl = authBaseUrl.replace(
      path: p.url.join(authBaseUrl.path, 'login'),
      queryParameters: {
        'continue': '$callbackUrl',
        'code_challenge': codeChallengeFor(codeVerifier),
        'code_challenge_method': 'S256',
      },
    );

    userPrompt(loginUrl.toString());

    final request = await _waitForCallback(
      server,
      callbackPath: callbackPath,
      timeout: timeout,
    );
    final code = await _extractAuthCode(request, expectedState: state);

    return await _exchangeAuthCode(
      httpClient: httpClient,
      authBaseUrl: authBaseUrl,
      code: code,
      codeVerifier: codeVerifier,
    );
  } finally {
    await server.close();
  }
}

/// 32 random bytes, base64url-encoded without padding: 43 characters, which
/// is within the 43–128 RFC 7636 allows for a code verifier and has the same
/// entropy it requires of one.
String _randomUrlSafeString() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// The S256 PKCE code challenge for [codeVerifier] (RFC 7636 section 4.2):
/// the base64url-encoded SHA-256 of the verifier, without padding.
String codeChallengeFor(String codeVerifier) {
  final digest = sha256.convert(ascii.encode(codeVerifier));
  return base64Url.encode(digest.bytes).replaceAll('=', '');
}

/// Listens on [server] for a request to [callbackPath] and returns it.
///
/// Responds to all other requests with 404 so they don't hang.
Future<HttpRequest> _waitForCallback(
  HttpServer server, {
  required String callbackPath,
  required Duration timeout,
}) async {
  final completer = Completer<HttpRequest>();
  final subscription = server.listen((request) {
    if (request.uri.path == callbackPath) {
      completer.complete(request);
    } else {
      request.response.statusCode = HttpStatus.notFound;
      unawaited(request.response.close());
    }
  });
  try {
    return await completer.future.timeout(
      timeout,
      onTimeout: () {
        throw const ShorebirdAuthException(
          'Timed out waiting for authentication response.',
        );
      },
    );
  } finally {
    await subscription.cancel();
  }
}

/// Sends a success page to the browser and extracts the auth code from the
/// callback [request].
///
/// Throws [ShorebirdAuthException] if the callback contains an error, does not
/// carry [expectedState], or is missing the auth code. The `state` check is
/// what stops a code from a login this CLI did not start (for example, a page
/// that sends the browser to this port) from being accepted.
Future<String> _extractAuthCode(
  HttpRequest request, {
  required String expectedState,
}) async {
  final code = request.uri.queryParameters['code'];
  final error = request.uri.queryParameters['error'];
  final state = request.uri.queryParameters['state'];

  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.html
    ..write(
      '<html><body><h1>Authentication complete.</h1> '
      '<p>You can close this window.</p></body></html>',
    );
  await request.response.close();

  if (error != null) {
    throw ShorebirdAuthException(
      'Authentication failed: $error',
    );
  }

  if (state != expectedState) {
    throw const ShorebirdAuthException(
      'Authentication failed: the response did not match this login request.',
    );
  }

  if (code == null) {
    throw const ShorebirdAuthException(
      'Authentication failed: no auth code received.',
    );
  }

  return code;
}

/// Refreshes Shorebird tokens using the refresh token.
///
/// POSTs to the auth service's /token endpoint with
/// `grant_type=refresh_token` and returns new [oauth2.AccessCredentials]
/// including a rotated refresh token.
Future<oauth2.AccessCredentials> refreshShorebirdCredentials(
  oauth2.AccessCredentials credentials,
  http.Client httpClient, {
  required Uri authBaseUrl,
}) async {
  final refreshToken = credentials.refreshToken;
  if (refreshToken == null) {
    throw const ShorebirdAuthException('No refresh token available.');
  }

  final tokenUrl = authBaseUrl.replace(
    path: p.url.join(authBaseUrl.path, 'token'),
  );

  final response = await httpClient.post(
    tokenUrl,
    body: {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    },
  );

  if (response.statusCode != HttpStatus.ok) {
    throw ShorebirdAuthException(
      'Token refresh failed (${response.statusCode}): ${response.body}',
      statusCode: response.statusCode,
    );
  }

  return _parseTokenResponse(response.body);
}

/// Exchanges an auth code for tokens by POSTing it, with the PKCE
/// [codeVerifier], to the auth service's /token endpoint.
Future<oauth2.AccessCredentials> _exchangeAuthCode({
  required http.Client httpClient,
  required Uri authBaseUrl,
  required String code,
  required String codeVerifier,
}) async {
  final tokenUrl = authBaseUrl.replace(
    path: p.url.join(authBaseUrl.path, 'token'),
  );

  final response = await httpClient.post(
    tokenUrl,
    body: {
      'grant_type': 'authorization_code',
      'code': code,
      'code_verifier': codeVerifier,
    },
  );

  if (response.statusCode != HttpStatus.ok) {
    throw ShorebirdAuthException(
      'Token exchange failed (${response.statusCode}): ${response.body}',
    );
  }

  return _parseTokenResponse(response.body);
}

/// Parses the JSON token response from the auth service into
/// [oauth2.AccessCredentials].
///
/// Validates that the `access_token` is a well-formed JWT and that its
/// issuer matches the expected JWT issuer from [ShorebirdEnv].
///
/// Expected JSON shape:
/// ```json
/// {
///   "access_token": "<JWT>",
///   "refresh_token": "sb_rt_...",
///   "token_type": "Bearer",
///   "expires_in": 900
/// }
/// ```
oauth2.AccessCredentials _parseTokenResponse(String responseBody) {
  final json = jsonDecode(responseBody) as Map<String, dynamic>;
  final accessTokenValue = json['access_token'] as String;
  final refreshToken = json['refresh_token'] as String?;
  final tokenType = json['token_type'] as String? ?? 'Bearer';
  final expiresIn = json['expires_in'] as int;

  // Validate the access token is a well-formed JWT.
  final Jwt jwt;
  try {
    jwt = Jwt.parse(accessTokenValue);
  } on FormatException catch (e) {
    throw ShorebirdAuthException('Invalid access token: ${e.message}');
  }

  // Validate the issuer matches the expected auth service.
  final expectedIssuer = shorebirdEnv.jwtIssuer;
  if (jwt.payload.iss != expectedIssuer) {
    throw ShorebirdAuthException(
      'Token issuer mismatch: expected $expectedIssuer, '
      'got ${jwt.payload.iss}',
    );
  }

  final expiry = clock.now().add(Duration(seconds: expiresIn)).toUtc();

  return oauth2.AccessCredentials(
    AccessToken(tokenType, accessTokenValue, expiry),
    refreshToken,
    // Shorebird auth doesn't use scopes.
    [],
  );
}

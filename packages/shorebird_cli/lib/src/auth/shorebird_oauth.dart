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

/// The OAuth client id the CLI is registered under with the auth service.
///
/// A public client (RFC 6749 section 2.1): it has no secret, and PKCE is what
/// binds a code to the login that asked for it.
const _clientId = 'shorebird-cli';

/// The scope the CLI requests: a full session acting as the user.
///
/// Released CLIs keep sending this until the next minimum-version bump, so it
/// must stay a scope the auth service accepts for `shorebird-cli`.
const _scope = 'api';

/// The path of the loopback redirect URI registered for [_clientId].
///
/// The auth service matches a loopback redirect on any port (RFC 8252 section
/// 7.3) but compares the path and query exactly, so the redirect URI carries
/// no query of its own.
const _callbackPath = '/callback';

/// Implements the full loopback login flow for Shorebird auth: an OAuth 2.0
/// authorization code request (RFC 6749 section 4.1) from a native app
/// (RFC 8252), with PKCE (RFC 7636).
///
/// 1. Binds a local HTTP server on localhost with a random port.
/// 2. Generates a PKCE code verifier and a `state` value.
/// 3. Constructs the authorization URL for the `shorebird-cli` client, with
///    the loopback redirect URI, the `api` scope, `state` and the S256 code
///    challenge.
/// 4. Calls [userPrompt] with the login URL.
/// 5. Waits for the auth service to redirect back with an auth code, and
///    rejects a callback whose `state` does not match or that carries an
///    `error`.
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
    final state = _randomUrlSafeString();
    final codeVerifier = _randomUrlSafeString();
    final redirectUri = Uri(
      scheme: 'http',
      host: 'localhost',
      port: server.port,
      path: _callbackPath,
    );
    final loginUrl = authBaseUrl.replace(
      path: p.url.join(authBaseUrl.path, 'login'),
      queryParameters: {
        'response_type': 'code',
        'client_id': _clientId,
        'redirect_uri': '$redirectUri',
        'scope': _scope,
        'state': state,
        'code_challenge': codeChallengeFor(codeVerifier),
        'code_challenge_method': 'S256',
      },
    );

    userPrompt(loginUrl.toString());

    final request = await _waitForCallback(
      server,
      callbackPath: _callbackPath,
      timeout: timeout,
    );
    final code = await _extractAuthCode(request, expectedState: state);

    return await _exchangeAuthCode(
      httpClient: httpClient,
      authBaseUrl: authBaseUrl,
      code: code,
      codeVerifier: codeVerifier,
      redirectUri: redirectUri,
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

/// Extracts the auth code from the callback [request] and tells the browser
/// how the login went.
///
/// Throws [ShorebirdAuthException] if the callback does not carry
/// [expectedState], carries an `error` (RFC 6749 section 4.1.2.1), or is
/// missing the auth code. The `state` check is what stops a code from a login
/// this CLI did not start (for example, a page that sends the browser to this
/// port) from being accepted. An error response is checked against `state`
/// too where it carries one, so a forged error is reported as a mismatch
/// rather than as the auth service's answer.
Future<String> _extractAuthCode(
  HttpRequest request, {
  required String expectedState,
}) async {
  final params = request.uri.queryParameters;
  final code = params['code'];
  final error = params['error'];
  final state = params['state'];

  final ShorebirdAuthException? failure;
  if (state != expectedState && (error == null || state != null)) {
    failure = const ShorebirdAuthException(
      'Authentication failed: the response did not match this login request.',
    );
  } else if (error != null) {
    final description = params['error_description'];
    failure = ShorebirdAuthException(
      'Authentication failed: $error'
      '${description == null ? '' : ' ($description)'}',
    );
  } else if (code == null) {
    failure = const ShorebirdAuthException(
      'Authentication failed: no auth code received.',
    );
  } else {
    failure = null;
  }

  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.html
    ..write(
      failure == null
          ? '<html><body><h1>Authentication complete.</h1> '
                '<p>You can close this window.</p></body></html>'
          : '<html><body><h1>Authentication failed.</h1> '
                '<p>Return to the terminal for details.</p></body></html>',
    );
  await request.response.close();

  if (failure != null) throw failure;
  return code!;
}

/// Refreshes Shorebird tokens using the refresh token.
///
/// POSTs to the auth service's /token endpoint with
/// `grant_type=refresh_token` and returns new [oauth2.AccessCredentials]
/// including a rotated refresh token.
///
/// Always names the `shorebird-cli` client: a session issued to a client must
/// name it at refresh, and the auth service ignores `client_id` for sessions
/// issued without one, which is every login made before the CLI registered as
/// a client.
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
      'client_id': _clientId,
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
///
/// [redirectUri] must be the one the authorization request sent; the auth
/// service refuses the exchange otherwise (RFC 6749 section 4.1.3).
Future<oauth2.AccessCredentials> _exchangeAuthCode({
  required http.Client httpClient,
  required Uri authBaseUrl,
  required String code,
  required String codeVerifier,
  required Uri redirectUri,
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
      'client_id': _clientId,
      'redirect_uri': '$redirectUri',
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
    // The granted `scope` in the response is not used: the CLI only ever
    // asks for one, and the server decides what the token may do.
    [],
  );
}

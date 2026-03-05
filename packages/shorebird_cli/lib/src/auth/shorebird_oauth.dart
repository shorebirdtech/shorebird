import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:googleapis_auth/auth_io.dart' as oauth2;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:jwt/jwt.dart';
import 'package:path/path.dart' as p;

/// Exception thrown when the Shorebird auth flow fails.
class ShorebirdAuthException implements Exception {
  /// Creates a [ShorebirdAuthException] with the given [message].
  const ShorebirdAuthException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'ShorebirdAuthException: $message';
}

/// Implements the full loopback login flow for Shorebird auth.
///
/// 1. Binds a local HTTP server on localhost with a random port.
/// 2. Constructs the login URL pointing to the auth service.
/// 3. Calls [userPrompt] with the login URL.
/// 4. Waits for the auth service to redirect back with an auth code.
/// 5. Exchanges the auth code for tokens via the auth service's /token endpoint.
/// 6. Returns the tokens as [oauth2.AccessCredentials].
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
    final loginUrl = authBaseUrl.replace(
      path: p.url.join(authBaseUrl.path, 'login'),
      queryParameters: {'continue': 'http://localhost:$port$callbackPath'},
    );

    userPrompt(loginUrl.toString());

    final request = await _waitForCallback(
      server,
      callbackPath: callbackPath,
      timeout: timeout,
    );
    final code = await _extractAuthCode(request);

    return await _exchangeAuthCode(
      httpClient: httpClient,
      authBaseUrl: authBaseUrl,
      code: code,
    );
  } finally {
    await server.close();
  }
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
/// Throws [ShorebirdAuthException] if the callback contains an error or is
/// missing the auth code.
Future<String> _extractAuthCode(HttpRequest request) async {
  final code = request.uri.queryParameters['code'];
  final error = request.uri.queryParameters['error'];

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
    );
  }

  return _parseTokenResponse(response.body, expectedIssuer: authBaseUrl);
}

/// Exchanges an auth code for tokens by POSTing to the auth service's
/// /token endpoint.
Future<oauth2.AccessCredentials> _exchangeAuthCode({
  required http.Client httpClient,
  required Uri authBaseUrl,
  required String code,
}) async {
  final tokenUrl = authBaseUrl.replace(
    path: p.url.join(authBaseUrl.path, 'token'),
  );

  final response = await httpClient.post(
    tokenUrl,
    body: {
      'grant_type': 'authorization_code',
      'code': code,
    },
  );

  if (response.statusCode != HttpStatus.ok) {
    throw ShorebirdAuthException(
      'Token exchange failed (${response.statusCode}): ${response.body}',
    );
  }

  return _parseTokenResponse(response.body, expectedIssuer: authBaseUrl);
}

/// Parses the JSON token response from the auth service into
/// [oauth2.AccessCredentials].
///
/// Validates that the `access_token` is a well-formed JWT and that its
/// issuer matches [expectedIssuer].
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
oauth2.AccessCredentials _parseTokenResponse(
  String responseBody, {
  required Uri expectedIssuer,
}) {
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
  final issuer = expectedIssuer.toString();
  if (jwt.payload.iss != issuer) {
    throw ShorebirdAuthException(
      'Token issuer mismatch: expected $issuer, '
      'got ${jwt.payload.iss}',
    );
  }

  final expiry = clock.now().add(Duration(seconds: expiresIn)).toUtc();

  return oauth2.AccessCredentials(
    AccessToken(tokenType, accessTokenValue, expiry),
    refreshToken,
    // Shorebird auth doesn't use scopes.
    [],
    // The access token IS the JWT — setting idToken ensures
    // AuthenticatedClient.send() picks it up as the Bearer token.
    idToken: accessTokenValue,
  );
}

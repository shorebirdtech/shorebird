import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart' as oauth2;
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

/// The OAuth client id the CLI is registered under with the auth service.
///
/// A public client (RFC 6749 section 2.1): it has no secret, and PKCE is what
/// binds a code to the login that asked for it. It is sent on every request
/// to the token endpoint, refreshes included: a session issued to a client
/// must name it, and the auth service ignores `client_id` for sessions issued
/// without one, which is every login made before the CLI registered as a
/// client.
const shorebirdCliClientId = 'shorebird-cli';

/// The scope the CLI requests: a full session acting as the user.
///
/// Released CLIs keep sending this until the next minimum-version bump, so it
/// must stay a scope the auth service accepts for `shorebird-cli`.
const shorebirdCliScope = 'api';

/// The path of the loopback redirect URI registered for
/// [shorebirdCliClientId].
///
/// The auth service matches a loopback redirect on any port (RFC 8252 section
/// 7.3) but compares the path and query exactly, so the redirect URI carries
/// no query of its own.
const _callbackPath = '/callback';

/// The auth service's token endpoint (RFC 6749 section 3.2).
Uri tokenEndpointFor(Uri authBaseUrl) => _endpoint(authBaseUrl, 'token');

Uri _endpoint(Uri authBaseUrl, String path) =>
    authBaseUrl.replace(path: p.url.join(authBaseUrl.path, path));

/// Implements the full loopback login flow for Shorebird auth: an OAuth 2.0
/// authorization code request (RFC 6749 section 4.1) from a native app
/// (RFC 8252), with PKCE (RFC 7636), using [oauth2.AuthorizationCodeGrant].
///
/// 1. Binds a local HTTP server on localhost with a random port.
/// 2. Builds the authorization URL for the `shorebird-cli` client, with the
///    loopback redirect URI, the `api` scope, a `state` value and the S256
///    code challenge.
/// 3. Calls [userPrompt] with the login URL.
/// 4. Waits for the auth service to redirect back, then hands the callback's
///    parameters to the grant, which checks `state`, rejects an `error`, and
///    exchanges the code and code verifier at the token endpoint.
/// 5. Calls [completeLogin], if given, with the credentials, so the caller
///    can finish the login (look up the user, save the credentials) before
///    the browser is told how it went.
/// 6. Sends the browser to the auth service's page for how the login went
///    (see [_loginResultPage]) and returns the credentials. The browser is
///    told the login succeeded only when every step, [completeLogin]
///    included, did.
///
/// Throws [oauth2.AuthorizationException] when the auth service answered with
/// an OAuth error, [FormatException] when the callback or the token response
/// is not a valid one, and [ShorebirdAuthException] when no callback arrives
/// within [timeout]. Whatever [completeLogin] throws is rethrown.
Future<oauth2.Credentials> obtainCredentialsViaLoopbackLogin({
  required http.Client httpClient,
  required Uri authBaseUrl,
  required void Function(String) userPrompt,
  Duration timeout = const Duration(minutes: 5),
  Future<void> Function(oauth2.Credentials credentials)? completeLogin,
}) async {
  HttpServer server;
  try {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  } on SocketException {
    server = await HttpServer.bind(InternetAddress.loopbackIPv6, 0);
  }
  try {
    final grant = oauth2.AuthorizationCodeGrant(
      shorebirdCliClientId,
      _endpoint(authBaseUrl, 'login'),
      tokenEndpointFor(authBaseUrl),
      httpClient: httpClient,
    );
    final redirectUri = Uri(
      scheme: 'http',
      host: 'localhost',
      port: server.port,
      path: _callbackPath,
    );
    final loginUrl = grant.getAuthorizationUrl(
      redirectUri,
      scopes: [shorebirdCliScope],
      state: _randomUrlSafeString(),
    );

    userPrompt(loginUrl.toString());

    final request = await _waitForCallback(
      server,
      callbackPath: _callbackPath,
      timeout: timeout,
    );
    final oauth2.Client client;
    try {
      client = await grant.handleAuthorizationResponse(
        request.uri.queryParameters,
      );
      await completeLogin?.call(client.credentials);
    } on Object {
      await _respondToBrowser(
        request,
        authBaseUrl: authBaseUrl,
        succeeded: false,
      );
      rethrow;
    }
    await _respondToBrowser(request, authBaseUrl: authBaseUrl, succeeded: true);
    return client.credentials;
  } finally {
    await server.close();
  }
}

/// The `grant_type` that polls `/token` for a device authorization
/// (RFC 8628 section 3.4).
const deviceCodeGrantType = 'urn:ietf:params:oauth:grant-type:device_code';

/// How much to lengthen the polling interval each time the auth service
/// answers `slow_down` (RFC 8628 section 3.5).
const deviceSlowDownIncrement = Duration(seconds: 5);

/// Waits for [duration]. Injected so tests need not wait for real.
typedef Sleep = Future<void> Function(Duration duration);

/// A device authorization the auth service has started (RFC 8628 section
/// 3.2): the code a person enters, and where they enter it.
class DeviceAuthorization {
  /// Creates a [DeviceAuthorization].
  const DeviceAuthorization({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
    this.verificationUriComplete,
  });

  /// Parses the auth service's JSON answer to `POST /device_authorization`.
  ///
  /// Throws [ShorebirdAuthException] when a required field is missing or has
  /// the wrong type.
  factory DeviceAuthorization.fromJson(Map<String, dynamic> json) {
    if (json case {
      'device_code': final String deviceCode,
      'user_code': final String userCode,
      'verification_uri': final String verificationUri,
      'expires_in': final int expiresIn,
    }) {
      final complete = json['verification_uri_complete'];
      final interval = json['interval'];
      return DeviceAuthorization(
        deviceCode: deviceCode,
        userCode: userCode,
        verificationUri: Uri.parse(verificationUri),
        verificationUriComplete: complete is String
            ? Uri.parse(complete)
            : null,
        expiresIn: Duration(seconds: expiresIn),
        // RFC 8628 section 3.2: five seconds when the server names none.
        interval: Duration(seconds: interval is int ? interval : 5),
      );
    }
    throw _unexpectedDeviceAuthorizationResponse;
  }

  /// The secret the CLI polls `/token` with. Never shown to the user.
  final String deviceCode;

  /// The code the user enters at [verificationUri].
  final String userCode;

  /// The page where the user enters [userCode].
  final Uri verificationUri;

  /// [verificationUri] with [userCode] already filled in, if the auth service
  /// provided one. The CLI does not show it: the auth service omits it, and
  /// does not accept it, for a session that acts as the user.
  final Uri? verificationUriComplete;

  /// How long [userCode] can be approved for.
  final Duration expiresIn;

  /// How long to wait between polls, until told to slow down.
  final Duration interval;
}

/// Implements the device authorization grant (RFC 8628) for the
/// `shorebird-cli` client, for machines that cannot open a local browser.
/// `package:oauth2` does not implement this grant.
///
/// 1. POSTs `client_id` and `scope` to the auth service's
///    `/device_authorization` endpoint.
/// 2. Calls [userPrompt] with the codes, so the user can approve the request
///    in a browser on any device.
/// 3. Polls `/token` with the device code every `interval`, lengthening the
///    interval by [deviceSlowDownIncrement] on each `slow_down`.
/// 4. Returns the tokens as [oauth2.Credentials] once the user approves, in
///    the same form the authorization code grant produces, so they refresh
///    the same way.
///
/// Throws [ShorebirdAuthException] if the user denies the request, the code
/// expires, or the auth service cannot be reached or refuses the request.
Future<oauth2.Credentials> obtainCredentialsViaDeviceLogin({
  required http.Client httpClient,
  required Uri authBaseUrl,
  required void Function(DeviceAuthorization) userPrompt,
  Sleep sleep = _sleep,
}) async {
  final authorization = await _startDeviceAuthorization(
    httpClient: httpClient,
    authBaseUrl: authBaseUrl,
  );
  userPrompt(authorization);

  final tokenEndpoint = tokenEndpointFor(authBaseUrl);
  final expiresAt = clock.now().add(authorization.expiresIn);
  var interval = authorization.interval;

  while (true) {
    await sleep(interval);
    if (!clock.now().isBefore(expiresAt)) throw _deviceCodeExpired;

    final requestedAt = DateTime.now();
    final http.Response response;
    try {
      response = await httpClient.post(
        tokenEndpoint,
        body: {
          'grant_type': deviceCodeGrantType,
          'device_code': authorization.deviceCode,
          'client_id': shorebirdCliClientId,
        },
      );
    } on Exception catch (e) {
      throw ShorebirdAuthException(
        'Could not reach the Shorebird auth service while waiting for '
        'approval ($e). Check your network connection and run '
        '`shorebird login` again.',
      );
    }

    if (response.statusCode == HttpStatus.ok) {
      return _parseTokenResponse(
        response.body,
        tokenEndpoint: tokenEndpoint,
        requestedAt: requestedAt,
      );
    }

    final error = _oauthError(response.body);
    switch (error) {
      case 'authorization_pending':
        continue;
      case 'slow_down':
        interval += deviceSlowDownIncrement;
        continue;
      case 'access_denied':
        throw const ShorebirdAuthException(
          'The login request was denied. Run `shorebird login` again to start '
          'a new one.',
        );
      case 'expired_token':
        throw _deviceCodeExpired;
      case 'invalid_grant':
        throw const ShorebirdAuthException(
          'The auth service no longer accepts this login request. Run '
          '`shorebird login` again to start a new one.',
        );
      default:
        throw ShorebirdAuthException(
          'Login failed (${response.statusCode}): ${response.body}',
        );
    }
  }
}

const _unexpectedDeviceAuthorizationResponse = ShorebirdAuthException(
  'The auth service sent an unexpected device authorization response.',
);

const _deviceCodeExpired = ShorebirdAuthException(
  'The login code expired before it was approved. Run `shorebird login` '
  'again to get a new code.',
);

Future<void> _sleep(Duration duration) => Future<void>.delayed(duration);

/// POSTs to the auth service's `/device_authorization` endpoint (RFC 8628
/// section 3.1) and returns what it answered.
Future<DeviceAuthorization> _startDeviceAuthorization({
  required http.Client httpClient,
  required Uri authBaseUrl,
}) async {
  final http.Response response;
  try {
    response = await httpClient.post(
      _endpoint(authBaseUrl, 'device_authorization'),
      body: {'client_id': shorebirdCliClientId, 'scope': shorebirdCliScope},
    );
  } on Exception catch (e) {
    throw ShorebirdAuthException(
      'Could not reach the Shorebird auth service ($e). Check your network '
      'connection and try again.',
    );
  }

  _throwUnlessOk(response, 'Could not start a login');

  final Object? json;
  try {
    json = jsonDecode(response.body);
  } on FormatException {
    throw _unexpectedDeviceAuthorizationResponse;
  }
  if (json is! Map<String, dynamic>) {
    throw _unexpectedDeviceAuthorizationResponse;
  }
  return DeviceAuthorization.fromJson(json);
}

/// The `error` of an RFC 6749 section 5.2 error response, or null when
/// [body] is not one.
String? _oauthError(String body) {
  try {
    final json = jsonDecode(body);
    if (json is Map<String, dynamic>) {
      final value = json['error'];
      if (value is String) return value;
    }
  } on FormatException {
    // Not JSON; the caller reports the body as is.
  }
  return null;
}

/// Parses a successful token response (RFC 6749 section 5.1) to the device
/// code grant into [oauth2.Credentials] that refresh at [tokenEndpoint].
///
/// [requestedAt] is when the request was sent, which `expires_in` counts
/// from, as `package:oauth2` counts it for the grants it implements.
///
/// Throws [ShorebirdAuthException] for a body of any other shape.
oauth2.Credentials _parseTokenResponse(
  String responseBody, {
  required Uri tokenEndpoint,
  required DateTime requestedAt,
}) {
  final Object? json;
  try {
    json = jsonDecode(responseBody);
  } on FormatException {
    throw _unexpectedTokenResponse;
  }
  if (json case {
    'access_token': final String accessToken,
    'token_type': final String tokenType,
    'expires_in': final int expiresIn,
  } when tokenType.toLowerCase() == 'bearer') {
    final refreshToken = json['refresh_token'];
    final scope = json['scope'];
    if (refreshToken is! String? || scope is! String?) {
      throw _unexpectedTokenResponse;
    }
    return oauth2.Credentials(
      accessToken,
      refreshToken: refreshToken,
      tokenEndpoint: tokenEndpoint,
      scopes: scope?.split(' ') ?? [shorebirdCliScope],
      expiration: requestedAt.add(Duration(seconds: expiresIn)),
    );
  }
  throw _unexpectedTokenResponse;
}

const _unexpectedTokenResponse = ShorebirdAuthException(
  'The auth service sent an unexpected token response.',
);

/// 32 random bytes, base64url-encoded without padding: the login's `state`.
String _randomUrlSafeString() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
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

/// Answers the browser's callback [request] by sending it to the auth
/// service's page for how the login went, which says whether it [succeeded]
/// and what to do next.
///
/// The page lives on the auth service rather than in this response so it can
/// be styled like the rest of sign-in and its next steps can change without a
/// CLI release. It carries only whether the login succeeded: the reason for a
/// failure is printed in the terminal, which the page points back to.
Future<void> _respondToBrowser(
  HttpRequest request, {
  required Uri authBaseUrl,
  required bool succeeded,
}) async {
  request.response
    ..statusCode = HttpStatus.seeOther
    ..headers.set(
      HttpHeaders.locationHeader,
      _loginResultPage(authBaseUrl, succeeded: succeeded).toString(),
    );
  await request.response.close();
}

/// The auth service's page the browser is sent to once the loopback login
/// has [succeeded], or not.
Uri _loginResultPage(Uri authBaseUrl, {required bool succeeded}) => _endpoint(
  authBaseUrl,
  'cli/login-result',
).replace(queryParameters: {'status': succeeded ? 'success' : 'failed'});

/// Revokes [refreshToken] at the auth service's /revoke endpoint (RFC 7009),
/// ending the session it belongs to. `package:oauth2` does not implement
/// revocation.
///
/// Names the `shorebird-cli` client for the same reason refreshes do (see
/// [shorebirdCliClientId]).
///
/// The auth service answers 200 whether or not the token was live (RFC 7009
/// section 2.2), so a 200 says only that nothing is left to revoke. Throws
/// [ShorebirdAuthException] for any other answer.
Future<void> revokeShorebirdRefreshToken(
  String refreshToken,
  http.Client httpClient, {
  required Uri authBaseUrl,
}) async {
  final response = await httpClient.post(
    _endpoint(authBaseUrl, 'revoke'),
    body: {
      'token': refreshToken,
      'token_type_hint': 'refresh_token',
      'client_id': shorebirdCliClientId,
    },
  );

  _throwUnlessOk(response, 'Token revocation failed');
}

/// Throws a [ShorebirdAuthException] carrying the status and body of
/// [response], prefixed with [failure], unless the auth service answered 200.
void _throwUnlessOk(http.Response response, String failure) {
  if (response.statusCode != HttpStatus.ok) {
    throw ShorebirdAuthException(
      '$failure (${response.statusCode}): ${response.body}',
    );
  }
}

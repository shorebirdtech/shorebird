import 'dart:async';
import 'dart:io';

import 'package:shorebird_cli/src/auth/shorebird_credentials.dart';

/// {@template shorebird_login_result}
/// The result of a Shorebird login flow.
/// {@endtemplate}
typedef ShorebirdLoginResult = ({String accessToken, String refreshToken});

/// Callback for performing the Shorebird login flow.
///
/// Starts a local HTTP server, opens auth.shorebird.dev/login in the browser,
/// and waits for the callback with tokens.
typedef PerformShorebirdLogin = Future<ShorebirdLoginResult> Function({
  required void Function(String url) prompt,
  String authServiceUrl,
});

/// Performs the Shorebird login flow via auth.shorebird.dev.
///
/// 1. Starts a local HTTP server on a random port
/// 2. Calls [prompt] with the auth URL for the user to visit
/// 3. Waits for the auth service to redirect back with tokens
/// 4. Returns the access token and refresh token
Future<ShorebirdLoginResult> performShorebirdLogin({
  required void Function(String url) prompt,
  String authServiceUrl = defaultAuthServiceUrl,
}) async {
  final completer = Completer<ShorebirdLoginResult>();

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  final redirectUri = Uri.encodeFull('http://localhost:$port');
  final loginUrl = '$authServiceUrl/login?redirect_uri=$redirectUri';

  prompt(loginUrl);

  server.listen((request) async {
    try {
      final accessToken = request.uri.queryParameters['access_token'];
      final refreshToken = request.uri.queryParameters['refresh_token'];

      if (accessToken != null && refreshToken != null) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(
            '<html><body><h2>Login successful!</h2>'
            '<p>You can close this window and return to the CLI.</p>'
            '</body></html>',
          );
        await request.response.close();

        if (!completer.isCompleted) {
          completer.complete(
            (accessToken: accessToken, refreshToken: refreshToken),
          );
        }
      } else {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Missing tokens');
        await request.response.close();
      }
    } on Exception catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }
  });

  try {
    return await completer.future;
  } finally {
    await server.close();
  }
}

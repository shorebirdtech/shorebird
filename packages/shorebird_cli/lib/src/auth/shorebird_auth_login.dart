import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shorebird_cli/src/auth/shorebird_credentials.dart';

/// {@template shorebird_login_result}
/// The result of a Shorebird login flow.
/// {@endtemplate}
typedef ShorebirdLoginResult = ({String accessToken, String refreshToken});

/// Callback for performing the Shorebird login flow.
///
/// Starts a local HTTP server, opens auth.shorebird.dev/login in the browser,
/// and waits for the callback with tokens.
typedef PerformShorebirdLogin =
    Future<ShorebirdLoginResult> Function({
      required void Function(String url) prompt,
      String authServiceUrl,
    });

/// Performs the Shorebird login flow via auth.shorebird.dev.
///
/// 1. Starts a local HTTP server on a random port
/// 2. Calls [prompt] with the auth URL for the user to visit
/// 3. Waits for the auth service to redirect back with an authorization code
/// 4. Exchanges the code for tokens via POST /token
/// 5. Returns the access token and refresh token
Future<ShorebirdLoginResult> performShorebirdLogin({
  required void Function(String url) prompt,
  String authServiceUrl = defaultAuthServiceUrl,
  http.Client? httpClient,
}) async {
  final completer = Completer<ShorebirdLoginResult>();
  final client = httpClient ?? http.Client();

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  final redirectUri = Uri.encodeFull('http://localhost:$port');
  final loginUrl = '$authServiceUrl/login?redirect_uri=$redirectUri';

  prompt(loginUrl);

  server.listen((request) async {
    try {
      final code = request.uri.queryParameters['code'];

      if (code != null) {
        // Exchange the authorization code for tokens.
        final tokenResponse = await client.post(
          Uri.parse('$authServiceUrl/token'),
          body: {
            'grant_type': 'authorization_code',
            'code': code,
          },
        );

        if (tokenResponse.statusCode != 200) {
          throw Exception(
            'Token exchange failed: '
            '${tokenResponse.statusCode} ${tokenResponse.body}',
          );
        }

        final body = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
        final accessToken = body['access_token'] as String;
        final refreshToken = body['refresh_token'] as String;

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
          ..write('Missing authorization code');
        await request.response.close();
      }
    } on Exception catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }
  });

  try {
    return await completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => throw TimeoutException(
        'Login timed out waiting for browser callback after 5 minutes.',
      ),
    );
  } finally {
    await server.close();
  }
}

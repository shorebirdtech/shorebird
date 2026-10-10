import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:googleapis_auth/auth_io.dart' as oauth2;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/shorebird_oauth.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import '../mocks.dart';

/// A JWT the token response parser accepts, issued by [issuer].
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

http.Response _json(Object body, {int status = HttpStatus.ok}) =>
    http.Response(jsonEncode(body), status);

http.Response _oauthError(String error) =>
    _json({'error': error, 'error_description': 'x'}, status: 400);

void main() {
  group('obtainCredentialsViaDeviceLogin', () {
    final authBaseUrl = Uri.parse('https://auth.shorebird.dev');
    final deviceAuthorizationJson = {
      'device_code': 'secret-device-code',
      'user_code': 'BEST-CAKE',
      'verification_uri': 'https://auth.shorebird.dev/device',
      'verification_uri_complete':
          'https://auth.shorebird.dev/device?user_code=BEST-CAKE',
      'expires_in': 900,
      'interval': 5,
    };
    final tokenJson = {
      'access_token': _buildTestJwt(),
      'refresh_token': 'sb_rt_refresh',
      'token_type': 'Bearer',
      'expires_in': 900,
      'scope': 'api',
    };

    late ShorebirdEnv shorebirdEnv;
    late DateTime now;
    late List<Duration> sleeps;
    late List<http.Request> requests;
    late List<DeviceAuthorization> prompts;

    setUp(() {
      shorebirdEnv = MockShorebirdEnv();
      when(
        () => shorebirdEnv.jwtIssuer,
      ).thenReturn('https://auth.shorebird.dev');
      now = DateTime.utc(2026, 10, 8, 12);
      sleeps = [];
      requests = [];
      prompts = [];
    });

    /// Runs the device login against an auth service that answers
    /// `/device_authorization` with [start] and each poll of `/token` with
    /// the next of [polls].
    Future<oauth2.AccessCredentials> login({
      http.Response? start,
      List<http.Response Function()> polls = const [],
    }) {
      var poll = 0;
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/device_authorization') {
          return start ?? _json(deviceAuthorizationJson);
        }
        expect(request.url.path, equals('/token'));
        return polls[poll++]();
      });
      return runScoped(
        () => withClock(
          Clock(() => now),
          () => obtainCredentialsViaDeviceLogin(
            httpClient: client,
            authBaseUrl: authBaseUrl,
            userPrompt: prompts.add,
            sleep: (duration) async {
              sleeps.add(duration);
              now = now.add(duration);
            },
          ),
        ),
        values: {shorebirdEnvRef.overrideWith(() => shorebirdEnv)},
      );
    }

    test('returns credentials once the request is approved', () async {
      final credentials = await login(
        polls: [
          () => _oauthError('authorization_pending'),
          () => _oauthError('authorization_pending'),
          () => _json(tokenJson),
        ],
      );

      expect(credentials.refreshToken, equals('sb_rt_refresh'));
      expect(credentials.accessToken.data, equals(tokenJson['access_token']));
      expect(credentials.accessToken.type, equals('Bearer'));
      expect(sleeps, equals(List.filled(3, const Duration(seconds: 5))));

      expect(prompts, hasLength(1));
      final prompt = prompts.single;
      expect(prompt.userCode, equals('BEST-CAKE'));
      expect(
        prompt.verificationUri,
        equals(Uri.parse('https://auth.shorebird.dev/device')),
      );
      expect(
        prompt.verificationUriComplete,
        equals(
          Uri.parse('https://auth.shorebird.dev/device?user_code=BEST-CAKE'),
        ),
      );
      expect(prompt.expiresIn, equals(const Duration(minutes: 15)));
    });

    test('asks for the api scope as shorebird-cli', () async {
      await login(polls: [() => _json(tokenJson)]);

      final start = requests.first;
      expect(start.method, equals('POST'));
      expect(
        start.url,
        equals(Uri.parse('https://auth.shorebird.dev/device_authorization')),
      );
      expect(
        start.bodyFields,
        equals({'client_id': 'shorebird-cli', 'scope': 'api'}),
      );

      final poll = requests.last;
      expect(poll.url, equals(Uri.parse('https://auth.shorebird.dev/token')));
      expect(
        poll.bodyFields,
        equals({
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'device_code': 'secret-device-code',
          'client_id': 'shorebird-cli',
        }),
      );
    });

    test('respects an authBaseUrl with a path', () async {
      final client = MockClient((request) async {
        requests.add(request);
        return request.url.path.endsWith('device_authorization')
            ? _json(deviceAuthorizationJson)
            : _json(tokenJson);
      });
      await runScoped(
        () => obtainCredentialsViaDeviceLogin(
          httpClient: client,
          authBaseUrl: Uri.parse('https://example.com/auth/'),
          userPrompt: (_) {},
          sleep: (_) async {},
        ),
        values: {shorebirdEnvRef.overrideWith(() => shorebirdEnv)},
      );
      expect(requests.map((r) => r.url.path), [
        '/auth/device_authorization',
        '/auth/token',
      ]);
    });

    test('waits between polls by default', () async {
      final client = MockClient(
        (request) async => request.url.path == '/device_authorization'
            ? _json({...deviceAuthorizationJson, 'interval': 0})
            : _json(tokenJson),
      );
      final credentials = await runScoped(
        () => obtainCredentialsViaDeviceLogin(
          httpClient: client,
          authBaseUrl: authBaseUrl,
          userPrompt: (_) {},
        ),
        values: {shorebirdEnvRef.overrideWith(() => shorebirdEnv)},
      );
      expect(credentials.refreshToken, equals('sb_rt_refresh'));
    });

    test('polls every five seconds when no interval is given', () async {
      await login(
        start: _json({...deviceAuthorizationJson}..remove('interval')),
        polls: [() => _json(tokenJson)],
      );
      expect(sleeps, equals([const Duration(seconds: 5)]));
    });

    test('accepts a response without verification_uri_complete', () async {
      await login(
        start: _json(
          {...deviceAuthorizationJson}..remove('verification_uri_complete'),
        ),
        polls: [() => _json(tokenJson)],
      );
      expect(prompts.single.verificationUriComplete, isNull);
    });

    test('lengthens the interval by five seconds on each slow_down', () async {
      await login(
        polls: [
          () => _oauthError('slow_down'),
          () => _oauthError('authorization_pending'),
          () => _oauthError('slow_down'),
          () => _json(tokenJson),
        ],
      );
      expect(
        sleeps.map((d) => d.inSeconds),
        equals([5, 10, 10, 15]),
      );
    });

    test('throws when the request is denied', () async {
      await expectLater(
        login(
          polls: [
            () => _oauthError('authorization_pending'),
            () => _oauthError('access_denied'),
          ],
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('denied. Run `shorebird login` again'),
          ),
        ),
      );
    });

    test('throws when the auth service says the code expired', () async {
      await expectLater(
        login(polls: [() => _oauthError('expired_token')]),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('expired before it was approved'),
          ),
        ),
      );
    });

    test('stops polling once the code has expired', () async {
      await expectLater(
        login(
          start: _json({...deviceAuthorizationJson, 'expires_in': 12}),
          polls: [
            () => _oauthError('authorization_pending'),
            () => _oauthError('authorization_pending'),
          ],
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('Run `shorebird login` again to get a new code'),
          ),
        ),
      );
      // Polled at 5s and 10s; at 15s the code had lapsed, so no third poll.
      expect(requests.where((r) => r.url.path == '/token'), hasLength(2));
    });

    test('throws when the device code is no longer accepted', () async {
      await expectLater(
        login(polls: [() => _oauthError('invalid_grant')]),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('no longer accepts this login request'),
          ),
        ),
      );
    });

    test('throws on an unexpected error from /token', () async {
      await expectLater(
        login(polls: [() => http.Response('oops', 500)]),
        throwsA(
          isA<ShorebirdAuthException>()
              .having((e) => e.message, 'message', contains('500'))
              .having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('carries the OAuth error of an unexpected refusal', () async {
      await expectLater(
        login(polls: [() => _oauthError('invalid_client')]),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.oauthError,
            'oauthError',
            'invalid_client',
          ),
        ),
      );
    });

    test('throws on a network error while polling', () async {
      await expectLater(
        login(
          polls: [() => throw const SocketException('no route to host')],
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('no route to host'),
              contains('Check your network connection'),
            ),
          ),
        ),
      );
    });

    test('throws on a network error starting the login', () async {
      final client = MockClient(
        (_) async => throw const SocketException('no route to host'),
      );
      await expectLater(
        obtainCredentialsViaDeviceLogin(
          httpClient: client,
          authBaseUrl: authBaseUrl,
          userPrompt: prompts.add,
          sleep: (_) async {},
        ),
        throwsA(
          isA<ShorebirdAuthException>().having(
            (e) => e.message,
            'message',
            contains('Could not reach the Shorebird auth service'),
          ),
        ),
      );
      expect(prompts, isEmpty);
    });

    test('throws when the auth service refuses to start a login', () async {
      await expectLater(
        login(
          start: _json({
            'error': 'unauthorized_client',
          }, status: HttpStatus.badRequest),
        ),
        throwsA(
          isA<ShorebirdAuthException>()
              .having((e) => e.message, 'message', contains('unauthorized'))
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
      expect(prompts, isEmpty);
    });

    for (final (description, body) in [
      ('is not JSON', 'not json'),
      ('is not an object', '[]'),
      ('is missing user_code', jsonEncode({'device_code': 'x'})),
    ]) {
      test('throws when the device authorization response $description', () {
        expect(
          login(start: http.Response(body, HttpStatus.ok)),
          throwsA(
            isA<ShorebirdAuthException>().having(
              (e) => e.message,
              'message',
              contains('unexpected device authorization response'),
            ),
          ),
        );
      });
    }
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/credential_source.dart';
import 'package:shorebird_cli/src/auth/oidc_credential_source.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

/// Supplies `id.token1`, `id.token2`, and so on, or throws [failure].
class _FakeSupplier implements SubjectTokenSupplier {
  int calls = 0;

  CredentialSourceException? failure;

  @override
  String get name => 'Test CI';

  @override
  Future<String> subjectToken() async {
    if (failure case final failure?) throw failure;
    calls++;
    return 'id.token$calls';
  }
}

void main() {
  useTempWorkingDirectory();

  const accessToken = 'sb_access_token';
  final authBaseUrl = Uri.parse('https://auth.shorebird.dev');
  final tokenEndpoint = Uri.parse('https://auth.shorebird.dev/token');

  late _FakeSupplier supplier;
  late http.Client exchangeClient;
  late int exchangeClientsCreated;
  late List<Duration> delays;
  late ShorebirdLogger logger;
  late OidcCredentialSource source;
  late DateTime now;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  R runWithOverrides<R>(R Function() body) {
    return withClock(
      Clock(() => now),
      () => runScoped(body, values: {loggerRef.overrideWith(() => logger)}),
    );
  }

  http.Response jsonResponse(Object body, {int status = HttpStatus.ok}) {
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
  }

  http.Response tokenResponse({String token = accessToken}) => jsonResponse({
    'access_token': token,
    'issued_token_type': 'urn:ietf:params:oauth:token-type:access_token',
    'token_type': 'Bearer',
    'expires_in': 900,
  });

  /// Answers the exchanges with [answers], in order, then a token. An
  /// [Exception] is thrown rather than answered.
  void answerExchangesWith(List<Object> answers) {
    var attempt = 0;
    when(
      () => exchangeClient.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) async {
      if (attempt < answers.length) {
        final answer = answers[attempt++];
        if (answer is Exception) throw answer;
        return answer as http.Response;
      }
      return tokenResponse();
    });
  }

  List<String?> subjectTokens() => verify(
    () => exchangeClient.post(
      any(),
      headers: any(named: 'headers'),
      body: captureAny(named: 'body'),
    ),
  ).captured.map((body) => (body as Map)['subject_token'] as String?).toList();

  Future<String> authorization() => runWithOverrides(source.authorization);

  Matcher throwsCredentialSourceException(Object? message) => throwsA(
    isA<CredentialSourceException>().having(
      (e) => e.message,
      'message',
      message,
    ),
  );

  setUp(() {
    supplier = _FakeSupplier();
    exchangeClient = MockHttpClient();
    exchangeClientsCreated = 0;
    delays = [];
    logger = MockShorebirdLogger();
    now = DateTime(2026, 10, 15, 12);
    source = OidcCredentialSource(
      subjectTokenSupplier: supplier,
      authBaseUrl: authBaseUrl,
      exchangeClient: () {
        exchangeClientsCreated++;
        return exchangeClient;
      },
      sleep: (duration) async => delays.add(duration),
    );
    answerExchangesWith([]);
  });

  test('is available and names its provider', () {
    expect(source.isAvailable, isTrue);
    expect(source.providerName, equals('Test CI'));
  });

  test('exchanges an ID token at the token endpoint', () async {
    await authorization();

    final captured = verify(
      () => exchangeClient.post(
        captureAny(),
        headers: any(named: 'headers'),
        body: captureAny(named: 'body'),
      ),
    ).captured;
    expect(captured[0], tokenEndpoint);
    expect(captured[1], {
      'grant_type': 'urn:ietf:params:oauth:grant-type:token-exchange',
      'subject_token_type': 'urn:ietf:params:oauth:token-type:id_token',
      'subject_token': 'id.token1',
    });
  });

  test('sends each exchange through a new client and closes it', () async {
    await authorization();

    expect(exchangeClientsCreated, equals(1));
    verify(() => exchangeClient.close()).called(1);
  });

  test('answers with the access token as the bearer', () async {
    expect(await authorization(), equals('Bearer $accessToken'));
  });

  test('reuses the access token until shortly before it expires', () async {
    await authorization();
    // 900s token: still more than 60s left at 839s.
    now = now.add(const Duration(seconds: 839));
    await authorization();

    expect(supplier.calls, equals(1));
    expect(subjectTokens(), ['id.token1']);
  });

  test('exchanges a new ID token within 60 seconds of expiry', () async {
    expect(await authorization(), 'Bearer $accessToken');

    answerExchangesWith([tokenResponse(token: 'sb_access_token2')]);
    now = now.add(const Duration(seconds: 840));
    expect(await authorization(), 'Bearer sb_access_token2');

    expect(supplier.calls, equals(2));
  });

  test('shares one exchange between concurrent requests', () async {
    final exchange = Completer<http.Response>();
    when(
      () => exchangeClient.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) => exchange.future);

    final answers = runWithOverrides(
      () => Future.wait([source.authorization(), source.authorization()]),
    );
    await Future<void>.delayed(Duration.zero);
    exchange.complete(tokenResponse());

    expect(await answers, ['Bearer $accessToken', 'Bearer $accessToken']);
    expect(supplier.calls, equals(1));
  });

  test('never logs the tokens', () async {
    await authorization();

    final messages = verify(() => logger.detail(captureAny())).captured;
    expect(messages, isNotEmpty);
    for (final message in messages) {
      expect(message, isNot(contains('id.token')));
      expect(message, isNot(contains(accessToken)));
    }
  });

  test('passes on a failure to get an ID token', () async {
    supplier.failure = const CredentialSourceException('No ID token.');

    await expectLater(
      authorization(),
      throwsCredentialSourceException('No ID token.'),
    );
    verifyNever(
      () => exchangeClient.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    );
  });

  group('when the auth service refuses the exchange', () {
    test('reports the error and its description', () async {
      answerExchangesWith([
        jsonResponse({
          'error': 'invalid_grant',
          'error_description': 'no trust rule matches',
        }, status: HttpStatus.badRequest),
      ]);

      await expectLater(
        authorization(),
        throwsA(
          isA<CredentialSourceException>()
              .having(
                (e) => e.message,
                'message',
                'The Shorebird auth service refused to sign in with Test CI '
                    'OIDC (invalid_grant: no trust rule matches).',
              )
              .having(
                (e) => e.hint,
                'hint',
                'Check that a Test CI trust rule at '
                    'https://console.shorebird.dev matches this job.',
              ),
        ),
      );
    });

    test('reports the error when there is no description', () async {
      answerExchangesWith([
        jsonResponse({'error': 'invalid_grant'}, status: 400),
      ]);

      await expectLater(
        authorization(),
        throwsCredentialSourceException(
          'The Shorebird auth service refused to sign in with Test CI OIDC '
          '(invalid_grant).',
        ),
      );
    });
  });

  test('reports a 4xx that is not an OAuth error', () async {
    answerExchangesWith([http.Response('Not found', HttpStatus.notFound)]);

    await expectLater(
      authorization(),
      throwsCredentialSourceException(
        'The Shorebird auth service could not sign in with Test CI OIDC '
        '(404).',
      ),
    );
  });

  test('reports an unexpected token response', () async {
    answerExchangesWith([
      jsonResponse({'token_type': 'Bearer'}),
    ]);

    await expectLater(
      authorization(),
      throwsCredentialSourceException(
        'The Shorebird auth service sent an unexpected token response.',
      ),
    );
  });

  group('retries', () {
    test('a retry after a 5xx uses a new ID token', () async {
      answerExchangesWith([
        http.Response('Bad gateway', HttpStatus.badGateway),
      ]);

      expect(await authorization(), 'Bearer $accessToken');
      expect(subjectTokens(), ['id.token1', 'id.token2']);
      expect(delays, [exchangeRetryDelays.first]);
    });

    test('a retry after a network failure uses a new ID token', () async {
      answerExchangesWith([
        const SocketException('connection reset'),
        http.ClientException('connection closed'),
      ]);

      await authorization();
      expect(subjectTokens(), ['id.token1', 'id.token2', 'id.token3']);
      expect(delays, exchangeRetryDelays.take(2));
    });

    test('gives up after the last retry', () async {
      answerExchangesWith([
        for (var i = 0; i <= exchangeRetryDelays.length; i++)
          http.Response('Unavailable', HttpStatus.serviceUnavailable),
      ]);

      await expectLater(
        authorization(),
        throwsCredentialSourceException(
          'The Shorebird auth service could not sign in with Test CI OIDC '
          '(503).',
        ),
      );
      expect(subjectTokens(), [
        for (var i = 1; i <= exchangeRetryDelays.length + 1; i++) 'id.token$i',
      ]);
      expect(delays, exchangeRetryDelays);
    });

    test('gives up on a network failure after the last retry', () async {
      answerExchangesWith([
        for (var i = 0; i <= exchangeRetryDelays.length; i++)
          const SocketException('no route to host'),
      ]);

      await expectLater(
        authorization(),
        throwsCredentialSourceException(
          startsWith(
            'Could not reach the Shorebird auth service to sign in with '
            'Test CI OIDC',
          ),
        ),
      );
    });

    test('does not retry an OAuth error', () async {
      answerExchangesWith([
        jsonResponse({'error': 'invalid_grant'}, status: 400),
      ]);

      await expectLater(
        authorization(),
        throwsA(isA<CredentialSourceException>()),
      );
      expect(subjectTokens(), ['id.token1']);
      expect(delays, isEmpty);
    });

    test('does not retry another failure to reach the auth service', () async {
      answerExchangesWith([const FormatException('not http')]);

      await expectLater(
        authorization(),
        throwsA(isA<CredentialSourceException>()),
      );
      expect(subjectTokens(), ['id.token1']);
    });
  });

  test('tries again on the next request after a failure', () async {
    answerExchangesWith([
      jsonResponse({'error': 'invalid_grant'}, status: 400),
    ]);
    await expectLater(
      authorization(),
      throwsA(isA<CredentialSourceException>()),
    );

    expect(await authorization(), 'Bearer $accessToken');
    expect(subjectTokens(), ['id.token1', 'id.token2']);
  });
}

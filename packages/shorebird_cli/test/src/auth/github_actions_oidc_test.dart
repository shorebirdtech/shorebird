// cspell:words fauth
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/credential_source.dart';
import 'package:shorebird_cli/src/auth/github_actions_oidc.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();

  const requestToken = 'gha-request-token';
  const idToken = 'gha.id.token';
  final idTokenRequestUrl = Uri.parse(
    'https://pipelines.actions.githubusercontent.com/abc/idtoken'
    '?api-version=2.0',
  );
  final audience = Uri.parse('https://auth.shorebird.dev');

  late http.Client httpClient;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    httpClient = MockHttpClient();
  });

  group('GitHubActionsSubjectTokenSupplier.fromEnvironment', () {
    GitHubActionsSubjectTokenSupplier? fromEnvironment(
      Map<String, String> environment,
    ) => GitHubActionsSubjectTokenSupplier.fromEnvironment(
      environment,
      audience: audience,
      httpClient: httpClient,
    );

    test('returns a supplier when both variables are set', () {
      expect(
        fromEnvironment({
          actionsIdTokenRequestUrlEnvVar: 'https://example.com/token?x=1',
          actionsIdTokenRequestTokenEnvVar: 'request-token',
        }),
        isNotNull,
      );
    });

    for (final (description, environment) in [
      ('neither variable is set', <String, String>{}),
      (
        'only the URL is set',
        {actionsIdTokenRequestUrlEnvVar: 'https://example.com/token'},
      ),
      (
        'only the token is set',
        {actionsIdTokenRequestTokenEnvVar: 'request-token'},
      ),
      (
        'the URL is empty',
        {
          actionsIdTokenRequestUrlEnvVar: '',
          actionsIdTokenRequestTokenEnvVar: 'request-token',
        },
      ),
      (
        'the token is empty',
        {
          actionsIdTokenRequestUrlEnvVar: 'https://example.com/token',
          actionsIdTokenRequestTokenEnvVar: '',
        },
      ),
      (
        'the URL cannot be parsed',
        {
          actionsIdTokenRequestUrlEnvVar: 'https://[::1',
          actionsIdTokenRequestTokenEnvVar: 'request-token',
        },
      ),
    ]) {
      test('returns null when $description', () {
        expect(fromEnvironment(environment), isNull);
      });
    }
  });

  group(GitHubActionsSubjectTokenSupplier, () {
    late GitHubActionsSubjectTokenSupplier supplier;

    void answerIdTokenRequestWith(http.Response Function() response) {
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => response());
    }

    Matcher throwsCredentialSourceException(String message) => throwsA(
      isA<CredentialSourceException>().having(
        (e) => e.message,
        'message',
        message,
      ),
    );

    setUp(() {
      supplier = GitHubActionsSubjectTokenSupplier(
        requestUrl: idTokenRequestUrl,
        requestToken: requestToken,
        audience: audience,
        httpClient: httpClient,
      );
      answerIdTokenRequestWith(
        () => http.Response(
          jsonEncode({'count': 1, 'value': idToken}),
          HttpStatus.ok,
        ),
      );
    });

    test('is named for messages', () {
      expect(supplier.name, equals('GitHub Actions'));
    });

    test('requests an ID token for the audience from GitHub', () async {
      expect(await supplier.subjectToken(), equals(idToken));

      final captured = verify(
        () =>
            httpClient.get(captureAny(), headers: captureAny(named: 'headers')),
      ).captured;
      expect(
        captured[0],
        Uri.parse(
          'https://pipelines.actions.githubusercontent.com/abc/idtoken'
          '?api-version=2.0&audience=https%3A%2F%2Fauth.shorebird.dev',
        ),
      );
      expect(
        captured[1],
        containsPair('Authorization', 'bearer $requestToken'),
      );
    });

    test('starts the query when the request URL has none', () async {
      supplier = GitHubActionsSubjectTokenSupplier(
        requestUrl: Uri.parse('https://example.com/idtoken'),
        requestToken: requestToken,
        audience: audience,
        httpClient: httpClient,
      );
      await supplier.subjectToken();

      final captured = verify(
        () => httpClient.get(captureAny(), headers: any(named: 'headers')),
      ).captured;
      expect(
        captured.single,
        Uri.parse(
          'https://example.com/idtoken?audience=https%3A%2F%2Fauth.shorebird.dev',
        ),
      );
    });

    test('reports when GitHub refuses to issue an ID token', () async {
      answerIdTokenRequestWith(
        () => http.Response('Forbidden', HttpStatus.forbidden),
      );
      await expectLater(
        supplier.subjectToken(),
        throwsA(
          isA<CredentialSourceException>()
              .having(
                (e) => e.message,
                'message',
                'GitHub Actions refused to issue an OIDC token (403).',
              )
              .having(
                (e) => e.hint,
                'hint',
                allOf(
                  contains("didn't accept ACTIONS_ID_TOKEN_REQUEST_TOKEN"),
                  isNot(contains('permissions')),
                ),
              ),
        ),
      );
    });

    test('reports when GitHub fails to issue an ID token', () async {
      answerIdTokenRequestWith(
        () => http.Response('Gateway Timeout', HttpStatus.gatewayTimeout),
      );
      await expectLater(
        supplier.subjectToken(),
        throwsA(
          isA<CredentialSourceException>()
              .having(
                (e) => e.message,
                'message',
                'GitHub Actions failed to issue an OIDC token (504).',
              )
              .having(
                (e) => e.hint,
                'hint',
                allOf(
                  contains("error on GitHub's side"),
                  isNot(contains('permissions')),
                ),
              ),
        ),
      );
    });

    for (final (description, body) in [
      ('no value', jsonEncode({'count': 0})),
      ('an empty value', jsonEncode({'value': ''})),
      ('a body that is not JSON', 'not json'),
    ]) {
      test('reports a response with $description', () async {
        answerIdTokenRequestWith(() => http.Response(body, HttpStatus.ok));
        await expectLater(
          supplier.subjectToken(),
          throwsCredentialSourceException(
            'GitHub Actions sent an unexpected OIDC token response.',
          ),
        );
      });
    }

    test('reports when GitHub cannot be reached', () async {
      when(
        () => httpClient.get(any(), headers: any(named: 'headers')),
      ).thenThrow(const SocketException('no route to host'));
      await expectLater(
        supplier.subjectToken(),
        throwsA(
          isA<CredentialSourceException>().having(
            (e) => e.message,
            'message',
            startsWith('Could not request an OIDC token from GitHub Actions'),
          ),
        ),
      );
    });

    test('never puts the tokens in a failure', () async {
      answerIdTokenRequestWith(
        () => http.Response(
          jsonEncode({'value': idToken, 'note': requestToken}),
          HttpStatus.forbidden,
        ),
      );
      try {
        await supplier.subjectToken();
        fail('expected a CredentialSourceException');
      } on CredentialSourceException catch (e) {
        for (final text in [e.message, e.hint, e.toString()]) {
          expect(text, isNot(contains(requestToken)));
          expect(text, isNot(contains(idToken)));
        }
      }
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockCodePushClient extends Mock implements CodePushClient {}

void main() {
  group('Auth', () {
    const idToken =
        '''eyJhbGciOiJSUzI1NiIsImN0eSI6IkpXVCJ9.eyJlbWFpbCI6InRlc3RAZW1haWwuY29tIn0.pD47BhF3MBLyIpfsgWCzP9twzC1HJxGukpcR36DqT6yfiOMHTLcjDbCjRLAnklWEHiT0BQTKTfhs8IousU90Fm5bVKObudfKu8pP5iZZ6Ls4ohDjTrXky9j3eZpZjwv8CnttBVgRfMJG-7YASTFRYFcOLUpnb4Zm5R6QdoCDUYg''';
    const email = 'test@email.com';
    const name = 'Jane Doe';
    const user = User(id: 42, email: email);
    const refreshToken = '';
    const scopes = <String>[];
    final accessToken = AccessToken(
      'Bearer',
      'accessToken',
      DateTime.now().add(const Duration(minutes: 10)).toUtc(),
    );

    final accessCredentials = AccessCredentials(
      accessToken,
      refreshToken,
      scopes,
      idToken: idToken,
    );

    late String credentialsDir;
    late http.Client httpClient;
    late CodePushClient codePushClient;
    late Auth auth;

    setUpAll(() {
      registerFallbackValue(_FakeBaseRequest());
    });

    Auth buildAuth() {
      return Auth(
        credentialsDir: credentialsDir,
        httpClient: httpClient,
        buildCodePushClient: ({Uri? hostedUri, http.Client? httpClient}) {
          return codePushClient;
        },
        obtainAccessCredentials: (clientId, scopes, client, userPrompt) async {
          return accessCredentials;
        },
      );
    }

    void writeCredentials() {
      File(p.join(credentialsDir, 'credentials.json'))
          .writeAsStringSync(jsonEncode(accessCredentials.toJson()));
    }

    setUp(() {
      credentialsDir = Directory.systemTemp.createTempSync().path;
      httpClient = _MockHttpClient();
      codePushClient = _MockCodePushClient();
      auth = buildAuth();

      when(() => codePushClient.getCurrentUser()).thenAnswer((_) async => user);
    });

    group('AuthenticatedClient', () {
      test('refreshes and uses new token when credentials are expired.',
          () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.ok,
          ),
        );

        final onRefreshCredentialsCalls = <AccessCredentials>[];
        final expiredCredentials = AccessCredentials(
          AccessToken(
            'Bearer',
            'accessToken',
            DateTime.now().subtract(const Duration(minutes: 1)).toUtc(),
          ),
          '',
          [],
          idToken: 'expiredIdToken',
        );

        final client = AuthenticatedClient(
          credentials: expiredCredentials,
          httpClient: httpClient,
          onRefreshCredentials: onRefreshCredentialsCalls.add,
          refreshCredentials: (clientId, credentials, client) async =>
              accessCredentials,
        );

        await client.get(Uri.parse('https://example.com'));

        expect(
          onRefreshCredentialsCalls,
          equals([
            isA<AccessCredentials>().having((c) => c.idToken, 'token', idToken)
          ]),
        );
        final captured = verify(() => httpClient.send(captureAny())).captured;
        expect(captured, hasLength(1));
        final request = captured.first as http.BaseRequest;
        expect(request.headers['Authorization'], equals('Bearer $idToken'));
      });

      test('uses valid token when credentials valid.', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.ok,
          ),
        );
        final onRefreshCredentialsCalls = <AccessCredentials>[];
        final client = AuthenticatedClient(
          credentials: accessCredentials,
          httpClient: httpClient,
          onRefreshCredentials: onRefreshCredentialsCalls.add,
        );

        await client.get(Uri.parse('https://example.com'));

        expect(onRefreshCredentialsCalls, isEmpty);
        final captured = verify(() => httpClient.send(captureAny())).captured;
        expect(captured, hasLength(1));
        final request = captured.first as http.BaseRequest;
        expect(request.headers['Authorization'], equals('Bearer $idToken'));
      });
    });

    group('client', () {
      test(
          'returns an authenticated client '
          'when credentials are present.', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.ok,
          ),
        );
        await auth.login((_) {});
        final client = auth.client;
        expect(client, isA<http.Client>());
        expect(client, isA<AuthenticatedClient>());

        await client.get(Uri.parse('https://example.com'));

        final captured = verify(() => httpClient.send(captureAny())).captured;
        expect(captured, hasLength(1));
        final request = captured.first as http.BaseRequest;
        expect(request.headers['Authorization'], equals('Bearer $idToken'));
      });

      test(
          'returns a plain http client '
          'when credentials are not present.', () async {
        final client = auth.client;
        expect(client, isA<http.Client>());
        expect(client, isNot(isA<AutoRefreshingAuthClient>()));
      });
    });

    group('login', () {
      test(
          'should set the email when claims are valid '
          'and current user exists', () async {
        await auth.login((_) {});
        expect(auth.email, email);
        expect(auth.isAuthenticated, isTrue);
        expect(buildAuth().email, email);
        expect(buildAuth().isAuthenticated, isTrue);
      });

      test('throws UserAlreadyLoggedInException if user is authenticated',
          () async {
        writeCredentials();
        auth = buildAuth();

        await expectLater(
          auth.login((_) {}),
          throwsA(isA<UserAlreadyLoggedInException>()),
        );

        expect(auth.email, isNotNull);
        expect(auth.isAuthenticated, isTrue);
      });

      test('should not set the email when user does not exist', () async {
        when(() => codePushClient.getCurrentUser())
            .thenAnswer((_) async => null);

        await expectLater(
          auth.login((_) {}),
          throwsA(isA<UserNotFoundException>()),
        );

        expect(auth.email, isNull);
        expect(auth.isAuthenticated, isFalse);
      });
    });

    group('signUp', () {
      test(
          'should set the email when claims are valid and user is successfully '
          'created', () async {
        when(() => codePushClient.getCurrentUser())
            .thenAnswer((_) async => null);
        when(() => codePushClient.createUser(name: any(named: 'name')))
            .thenAnswer((_) async => user);

        final newUser = await auth.signUp(
          authPrompt: (_) {},
          namePrompt: () => name,
        );
        expect(user, newUser);
        expect(auth.email, email);
        expect(auth.isAuthenticated, isTrue);
        expect(buildAuth().email, email);
        expect(buildAuth().isAuthenticated, isTrue);
      });

      test('throws UserAlreadyLoggedInException if user is authenticated',
          () async {
        writeCredentials();
        auth = buildAuth();

        await expectLater(
          auth.signUp(
            authPrompt: (_) {},
            namePrompt: () => name,
          ),
          throwsA(isA<UserAlreadyLoggedInException>()),
        );

        expect(auth.email, isNotNull);
        expect(auth.isAuthenticated, isTrue);
      });

      test('throws UserAlreadyExistsException if user already exists',
          () async {
        when(() => codePushClient.getCurrentUser())
            .thenAnswer((_) async => user);

        await expectLater(
          auth.signUp(
            authPrompt: (_) {},
            namePrompt: () => name,
          ),
          throwsA(isA<UserAlreadyExistsException>()),
        );
        verifyNever(() => codePushClient.createUser(name: any(named: 'name')));
        expect(auth.email, isNull);
        expect(auth.isAuthenticated, isFalse);
      });

      test('throws exception if createUser fails', () async {
        when(() => codePushClient.getCurrentUser())
            .thenAnswer((_) async => null);
        when(() => codePushClient.createUser(name: any(named: 'name')))
            .thenThrow(Exception('oh no!'));

        await expectLater(
          auth.signUp(
            authPrompt: (_) {},
            namePrompt: () => name,
          ),
          throwsA(isA<Exception>()),
        );
        expect(auth.email, isNull);
        expect(auth.isAuthenticated, isFalse);
      });

      test(
        "throws exception if credentials email doesn't match current user",
        () async {
          when(() => codePushClient.getCurrentUser()).thenAnswer(
            (_) async => const User(
              id: 123,
              email: 'email@email.com',
            ),
          );

          await expectLater(auth.login((_) {}), throwsException);

          expect(auth.email, isNull);
          expect(auth.isAuthenticated, isFalse);
        },
      );

      test(
        'does not fetch current user if verifyEmail is false',
        () async {
          await auth.login((_) {}, verifyEmail: false);
          verifyNever(() => codePushClient.getCurrentUser());
          expect(buildAuth().email, email);
          expect(buildAuth().isAuthenticated, isTrue);
        },
      );
    });

    group('logout', () {
      test('clears session and wipes state', () async {
        await auth.login((_) {});
        expect(auth.email, email);
        expect(auth.isAuthenticated, isTrue);

        auth.logout();
        expect(auth.email, isNull);
        expect(auth.isAuthenticated, isFalse);
        expect(buildAuth().email, isNull);
        expect(buildAuth().isAuthenticated, isFalse);
      });
    });

    group('close', () {
      test('closes the underlying httpClient', () {
        auth.close();
        verify(() => httpClient.close()).called(1);
      });
    });
  });
}

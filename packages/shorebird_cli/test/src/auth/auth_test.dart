import 'dart:io';

import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:test/test.dart';

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAccessCredentials extends Mock implements AccessCredentials {}

void main() {
  group('Auth', () {
    const idToken =
        '''eyJhbGciOiJSUzI1NiIsImN0eSI6IkpXVCJ9.eyJlbWFpbCI6InRlc3RAZW1haWwuY29tIn0.pD47BhF3MBLyIpfsgWCzP9twzC1HJxGukpcR36DqT6yfiOMHTLcjDbCjRLAnklWEHiT0BQTKTfhs8IousU90Fm5bVKObudfKu8pP5iZZ6Ls4ohDjTrXky9j3eZpZjwv8CnttBVgRfMJG-7YASTFRYFcOLUpnb4Zm5R6QdoCDUYg''';
    const email = 'test@email.com';
    final validCredentials = AccessCredentials(
      AccessToken(
        'Bearer',
        'accessToken',
        DateTime.now().add(const Duration(minutes: 10)).toUtc(),
      ),
      '',
      [],
      idToken: idToken,
    );

    late http.Client httpClient;
    late AccessCredentials accessCredentials;
    late Auth auth;

    setUpAll(() {
      registerFallbackValue(_FakeBaseRequest());
    });

    setUp(() {
      httpClient = _MockHttpClient();
      accessCredentials = _MockAccessCredentials();
      auth = Auth(
        httpClient: httpClient,
        obtainAccessCredentials: (clientId, scopes, client, userPrompt) async {
          return validCredentials;
        },
      )..logout();
    });

    group('AuthenticatedClient', () {
      test('when credentials are present and expired.', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.ok,
          ),
        );

        final refreshCallbacks = <AccessCredentials>[];
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
          onRefreshCallback: refreshCallbacks.add,
          refreshCredentials: (clientId, credentials, client) async =>
              validCredentials,
        );

        await client.get(Uri.parse('https://example.com'));

        expect(
          refreshCallbacks,
          equals([
            isA<AccessCredentials>().having((c) => c.idToken, 'token', idToken)
          ]),
        );
        final captured = verify(() => httpClient.send(captureAny())).captured;
        expect(captured, hasLength(1));
        final request = captured.first as http.BaseRequest;
        expect(request.headers['Authorization'], equals('Bearer $idToken'));
      });

      test('when credentials are present and valid.', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.ok,
          ),
        );
        final refreshCallbacks = <AccessCredentials>[];
        final client = AuthenticatedClient(
          credentials: validCredentials,
          httpClient: httpClient,
          onRefreshCallback: refreshCallbacks.add,
        );

        await client.get(Uri.parse('https://example.com'));

        expect(refreshCallbacks, isEmpty);
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
      test('should set the user when claims are valid', () async {
        when(() => accessCredentials.idToken).thenReturn(idToken);
        await auth.login((_) {});
        expect(auth.user, isA<User>().having((u) => u.email, 'email', email));
        expect(auth.isAuthenticated, isTrue);
        expect(
          Auth().user,
          isA<User>().having((u) => u.email, 'email', email),
        );
        expect(Auth().isAuthenticated, isTrue);
      });

      test('should not set the user when token is null', () async {
        when(() => accessCredentials.idToken).thenReturn(null);
        auth = Auth(
          httpClient: httpClient,
          obtainAccessCredentials:
              (clientId, scopes, client, userPrompt) async => accessCredentials,
        );
        await expectLater(
          auth.login((_) {}),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'description',
              'Exception: Missing JWT',
            ),
          ),
        );
        expect(auth.user, isNull);
        expect(auth.isAuthenticated, isFalse);
      });

      test('should not set the user when token is empty', () async {
        when(() => accessCredentials.idToken).thenReturn('');
        auth = Auth(
          httpClient: httpClient,
          obtainAccessCredentials:
              (clientId, scopes, client, userPrompt) async => accessCredentials,
        );
        await expectLater(
          auth.login((_) {}),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'description',
              'Exception: Invalid JWT',
            ),
          ),
        );
        expect(auth.user, isNull);
        expect(auth.isAuthenticated, isFalse);
      });

      test('should not set the user when token claims are malformed', () async {
        when(() => accessCredentials.idToken).thenReturn(
          '''eyJhbGciOiJSUzI1NiIsImN0eSI6IkpXVCJ9.eyJmb28iOiJiYXIifQ.LaR0JfOiDrS1AuABC38kzxpSjRLJ_OtfOkZ8hL6I1GPya-cJYwsmqhi5eMBwEbpYHcJhguG5l56XM6dW8xjdK7JbUN6_53gHBosSnL-Ccf29oW71Ado9sxO17YFQyihyMofJ_v78BPVy2H5O10hNjRn_M0JnnAe0Fvd2VrInlIE''',
        );
        auth = Auth(
          httpClient: httpClient,
          obtainAccessCredentials:
              (clientId, scopes, client, userPrompt) async => accessCredentials,
        );
        await expectLater(
          auth.login((_) {}),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'description',
              'Exception: Malformed claims',
            ),
          ),
        );
        expect(auth.user, isNull);
        expect(auth.isAuthenticated, isFalse);
      });
    });

    group('logout', () {
      test('clears session and wipes state', () async {
        await auth.login((_) {});
        expect(auth.user, isA<User>().having((u) => u.email, 'email', email));
        expect(auth.isAuthenticated, isTrue);

        auth.logout();
        expect(auth.user, isNull);
        expect(auth.isAuthenticated, isFalse);
        expect(Auth().user, isNull);
        expect(Auth().isAuthenticated, isFalse);
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

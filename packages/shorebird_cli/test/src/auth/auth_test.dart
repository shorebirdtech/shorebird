import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('Auth', () {
    const idToken =
        '''eyJhbGciOiJSUzI1NiIsImN0eSI6IkpXVCJ9.eyJlbWFpbCI6InRlc3RAZW1haWwuY29tIn0.pD47BhF3MBLyIpfsgWCzP9twzC1HJxGukpcR36DqT6yfiOMHTLcjDbCjRLAnklWEHiT0BQTKTfhs8IousU90Fm5bVKObudfKu8pP5iZZ6Ls4ohDjTrXky9j3eZpZjwv8CnttBVgRfMJG-7YASTFRYFcOLUpnb4Zm5R6QdoCDUYg''';
    const email = 'test@email.com';
    final credentials = AccessCredentials(
      AccessToken('Bearer', 'accessToken', DateTime.now().toUtc()),
      'refreshToken',
      [],
      idToken: idToken,
    );

    late http.Client httpClient;
    late Auth auth;

    setUp(() {
      httpClient = _MockHttpClient();
      auth = Auth(
        httpClient: httpClient,
        obtainAccessCredentials: (clientId, scopes, client, userPrompt) async {
          return credentials;
        },
      )..logout();
    });

    group('client', () {
      test(
          'returns an auto-refreshing client '
          'when credentials are present.', () async {
        await auth.login((_) {});
        final client = auth.client;
        expect(client, isA<http.Client>());
        expect(client, isA<AutoRefreshingAuthClient>());
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
      test('should set the user', () async {
        await auth.login((_) {});
        expect(auth.user, isA<User>().having((u) => u.email, 'email', email));
        expect(auth.isAuthenticated, isTrue);
        expect(
          Auth().user,
          isA<User>().having((u) => u.email, 'email', email),
        );
        expect(Auth().isAuthenticated, isTrue);
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

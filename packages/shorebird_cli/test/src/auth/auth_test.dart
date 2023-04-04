import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('Auth', () {
    final credentials = AccessCredentials(
      AccessToken('bearer', 'token', DateTime.now().toUtc()),
      'refreshToken',
      [],
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

    group('login', () {
      test('should set the credentials', () async {
        await auth.login((_) {});
        expect(
          auth.credentials,
          isA<AccessCredentials>().having(
            (c) => c.accessToken.data,
            'accessToken',
            credentials.accessToken.data,
          ),
        );
        expect(
          Auth().credentials,
          isA<AccessCredentials>().having(
            (c) => c.accessToken.data,
            'accessToken',
            credentials.accessToken.data,
          ),
        );
      });
    });

    group('logout', () {
      test('clears session and wipes state', () async {
        await auth.login((_) {});
        expect(
          auth.credentials,
          isA<AccessCredentials>().having(
            (c) => c.accessToken.data,
            'accessToken',
            credentials.accessToken.data,
          ),
        );

        auth.logout();
        expect(auth.credentials, isNull);
        expect(Auth().credentials, isNull);
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

import 'dart:convert';
import 'dart:io' hide Platform;

import 'package:cli_util/cli_util.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as oauth2;
import 'package:http/http.dart' as http;
import 'package:jwt/jwt.dart' show Jwt, JwtPayload;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../fakes.dart';
import '../mocks.dart';

const googleJwtIssuer = 'https://accounts.google.com';
const microsoftJwtIssuer =
    'https://login.microsoftonline.com/9188040d-6c67-4c5b-b112-36a304b66dad/v2.0';

void main() {
  group('scoped', () {
    test('creates instance with default constructor', () {
      final instance = runScoped(
        () => auth,
        values: {
          authRef,
          httpClientRef.overrideWith(MockHttpClient.new),
        },
      );
      expect(
        instance.credentialsFilePath,
        p.join(applicationConfigHome(executableName), 'credentials.json'),
      );
    });
  });

  group('JwtClaims', () {
    group('email', () {
      test('returns null when idToken is not a valid jwt', () {
        final credentials = oauth2.AccessCredentials(
          oauth2.AccessToken(
            'Bearer',
            'accessToken',
            DateTime.now().add(const Duration(minutes: 10)).toUtc(),
          ),
          '',
          [],
          idToken: 'not a valid jwt',
        );

        expect(credentials.email, isNull);
      });
    });
  });

  group('OauthAuthProvider', () {
    late Jwt jwt;
    late JwtPayload payload;

    setUp(() {
      payload = MockJwtPayload();
      jwt = Jwt(
        header: MockJwtHeader(),
        payload: payload,
        signature: 'signature',
      );
    });

    group('authProvider', () {
      group('when issuer is login.microsoft.online', () {
        setUp(() {
          when(() => payload.iss).thenReturn(microsoftJwtIssuer);
        });

        test('returns AuthProvider.microsoft', () {
          expect(jwt.authProvider, equals(AuthProvider.microsoft));
        });
      });

      group('when issuer is accounts.google.com', () {
        setUp(() {
          when(() => payload.iss).thenReturn(googleJwtIssuer);
        });

        test('returns AuthProvider.google', () {
          expect(jwt.authProvider, equals(AuthProvider.google));
        });
      });

      group('when issuer is unknown', () {
        setUp(() {
          when(() => payload.iss).thenReturn('https://example.com');
        });

        test('throws exception', () {
          expect(
            () => jwt.authProvider,
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                'Exception: Unknown jwt issuer: https://example.com',
              ),
            ),
          );
        });
      });
    });
  });

  group(Auth, () {
    const idToken =
        '''eyJhbGciOiJIUzI1NiIsImtpZCI6IjEyMzQiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20iLCJhenAiOiI1MjMzMDIyMzMyOTMtZWlhNWFudG0wdGd2ZWsyNDB0NDZvcmN0a3RpYWJyZWsuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJhdWQiOiI1MjMzMDIyMzMyOTMtZWlhNWFudG0wdGd2ZWsyNDB0NDZvcmN0a3RpYWJyZWsuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJzdWIiOiIxMjM0NSIsImhkIjoic2hvcmViaXJkLmRldiIsImVtYWlsIjoidGVzdEBlbWFpbC5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwiaWF0IjoxMjM0LCJleHAiOjY3ODl9.MYbITALvKsGYTYjw1o7AQ0ObkqRWVBSr9cFYJrvA46g''';
    const refreshToken = 'shorebird-token';
    const ciToken = CiToken(
      refreshToken: refreshToken,
      authProvider: AuthProvider.google,
    );
    const email = 'test@email.com';
    const user = User(
      id: 42,
      email: email,
      jwtIssuer: googleJwtIssuer,
    );
    const scopes = <String>[];
    final accessToken = oauth2.AccessToken(
      'Bearer',
      'accessToken',
      DateTime.now().add(const Duration(minutes: 10)).toUtc(),
    );

    late oauth2.AccessCredentials accessCredentials;
    late String credentialsDir;
    late http.Client httpClient;
    late CodePushClient codePushClient;
    late Logger logger;
    late Auth auth;
    late Platform platform;

    setUpAll(() {
      registerFallbackValue(FakeBaseRequest());
    });

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          httpClientRef.overrideWith(() => httpClient),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
        },
      );
    }

    Auth buildAuth() {
      return runWithOverrides(
        () => Auth(
          credentialsDir: credentialsDir,
          httpClient: httpClient,
          buildCodePushClient: ({Uri? hostedUri, http.Client? httpClient}) {
            return codePushClient;
          },
          obtainAccessCredentials: (
            clientId,
            scopes,
            client,
            userPrompt, {
            AuthEndpoints authEndpoints = const GoogleAuthEndpoints(),
          }) async {
            return accessCredentials;
          },
        ),
      );
    }

    void writeCredentials() {
      File(
        p.join(credentialsDir, 'credentials.json'),
      ).writeAsStringSync(jsonEncode(accessCredentials.toJson()));
    }

    setUp(() {
      accessCredentials = oauth2.AccessCredentials(
        accessToken,
        refreshToken,
        scopes,
        idToken: idToken,
      );
      credentialsDir = Directory.systemTemp.createTempSync().path;
      httpClient = MockHttpClient();
      codePushClient = MockCodePushClient();
      logger = MockLogger();
      platform = MockPlatform();

      when(() => codePushClient.getCurrentUser()).thenAnswer((_) async => user);
      when(() => platform.environment).thenReturn(<String, String>{});

      auth = buildAuth();
    });

    group('AuthenticatedClient', () {
      group('token', () {
        test('does not require an onRefreshCredentials callback', () {
          expect(
            () => AuthenticatedClient.token(
              token: ciToken,
              httpClient: httpClient,
              refreshCredentials: (
                clientId,
                credentials,
                client, {
                AuthEndpoints authEndpoints = const GoogleAuthEndpoints(),
              }) async =>
                  accessCredentials,
            ),
            returnsNormally,
          );
        });

        test('refreshes and uses new token when credentials are expired.',
            () async {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.ok,
            ),
          );

          final onRefreshCredentialsCalls = <oauth2.AccessCredentials>[];

          final client = AuthenticatedClient.token(
            token: ciToken,
            httpClient: httpClient,
            onRefreshCredentials: onRefreshCredentialsCalls.add,
            refreshCredentials: (
              clientId,
              credentials,
              client, {
              AuthEndpoints authEndpoints = const GoogleAuthEndpoints(),
            }) async =>
                accessCredentials,
          );

          await runWithOverrides(
            () => client.get(Uri.parse('https://example.com')),
          );

          expect(
            onRefreshCredentialsCalls,
            equals([
              isA<oauth2.AccessCredentials>()
                  .having((c) => c.idToken, 'token', idToken),
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
          final onRefreshCredentialsCalls = <oauth2.AccessCredentials>[];
          final client = AuthenticatedClient.token(
            token: ciToken,
            httpClient: httpClient,
            onRefreshCredentials: onRefreshCredentialsCalls.add,
            refreshCredentials: (
              clientId,
              credentials,
              client, {
              AuthEndpoints authEndpoints = const GoogleAuthEndpoints(),
            }) async =>
                accessCredentials,
          );

          await runWithOverrides(
            () async {
              await client.get(Uri.parse('https://example.com'));
              await client.get(Uri.parse('https://example.com'));
            },
          );

          expect(onRefreshCredentialsCalls.length, equals(1));
          final captured = verify(() => httpClient.send(captureAny())).captured;
          expect(captured, hasLength(2));
          var request = captured.first as http.BaseRequest;
          expect(request.headers['Authorization'], equals('Bearer $idToken'));
          request = captured.last as http.BaseRequest;
          expect(request.headers['Authorization'], equals('Bearer $idToken'));
        });
      });

      group('credentials', () {
        test('refreshes and uses new token when credentials are expired.',
            () async {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.ok,
            ),
          );

          const expiredIdToken =
              '''eyJhbGciOiJIUzI1NiIsImtpZCI6IjEyMzQiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20iLCJhenAiOiI1MjMzMDIyMzMyOTMtZWlhNWFudG0wdGd2ZWsyNDB0NDZvcmN0a3RpYWJyZWsuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJhdWQiOiI1MjMzMDIyMzMyOTMtZWlhNWFudG0wdGd2ZWsyNDB0NDZvcmN0a3RpYWJyZWsuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJzdWIiOiIxMjM0NSIsImhkIjoic2hvcmViaXJkLmRldiIsImVtYWlsIjoidGVzdEBlbWFpbC5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwiaWF0IjoxMjM0LCJleHAiOjY3ODl9.MYbITALvKsGYTYjw1o7AQ0ObkqRWVBSr9cFYJrvA46g''';
          final onRefreshCredentialsCalls = <oauth2.AccessCredentials>[];
          final expiredCredentials = oauth2.AccessCredentials(
            oauth2.AccessToken(
              'Bearer',
              'accessToken',
              DateTime.now().subtract(const Duration(minutes: 1)).toUtc(),
            ),
            '',
            [],
            idToken: expiredIdToken,
          );

          final client = AuthenticatedClient.credentials(
            credentials: expiredCredentials,
            httpClient: httpClient,
            onRefreshCredentials: onRefreshCredentialsCalls.add,
            refreshCredentials: (
              clientId,
              credentials,
              client, {
              AuthEndpoints authEndpoints = const GoogleAuthEndpoints(),
            }) async =>
                accessCredentials,
          );

          await runWithOverrides(
            () => client.get(Uri.parse('https://example.com')),
          );

          expect(
            onRefreshCredentialsCalls,
            equals([
              isA<oauth2.AccessCredentials>()
                  .having((c) => c.idToken, 'token', idToken),
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
          final onRefreshCredentialsCalls = <oauth2.AccessCredentials>[];
          final client = AuthenticatedClient.credentials(
            credentials: accessCredentials,
            httpClient: httpClient,
            onRefreshCredentials: onRefreshCredentialsCalls.add,
          );

          await runWithOverrides(
            () => client.get(Uri.parse('https://example.com')),
          );

          expect(onRefreshCredentialsCalls, isEmpty);
          final captured = verify(() => httpClient.send(captureAny())).captured;
          expect(captured, hasLength(1));
          final request = captured.first as http.BaseRequest;
          expect(request.headers['Authorization'], equals('Bearer $idToken'));
        });
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
        await auth.login(AuthProvider.google, prompt: (_) {});
        final client = auth.client;
        expect(client, isA<http.Client>());
        expect(client, isA<AuthenticatedClient>());

        await runWithOverrides(
          () => client.get(Uri.parse('https://example.com')),
        );

        final captured = verify(() => httpClient.send(captureAny())).captured;
        expect(captured, hasLength(1));
        final request = captured.first as http.BaseRequest;
        expect(request.headers['Authorization'], equals('Bearer $idToken'));
      });

      group('when token is invalid', () {
        setUp(() {
          when(() => platform.environment).thenReturn(
            <String, String>{shorebirdTokenEnvVar: 'not a base64 string'},
          );
        });

        test('prints warning message when token string is not valid base64',
            () async {
          auth = buildAuth();
          verify(
            () => logger.warn('''
SHOREBIRD_TOKEN needs to be updated before the next major release.
Run `shorebird login:ci` to obtain a new token.'''),
          ).called(1);
        });
      });

      test(
          'returns an authenticated client '
          'when a token and token provider is present.', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.ok,
          ),
        );
        when(() => platform.environment).thenReturn(
          <String, String>{shorebirdTokenEnvVar: ciToken.toBase64()},
        );
        auth = buildAuth();
        final client = auth.client;
        expect(client, isA<http.Client>());
        expect(client, isA<AuthenticatedClient>());
      });

      test('returns a plain http client when credentials are not present.',
          () async {
        final client = auth.client;
        expect(client, isA<http.Client>());
        expect(client, isNot(isA<oauth2.AutoRefreshingAuthClient>()));
      });
    });

    group('login', () {
      test('should set the email when claims are valid and current user exists',
          () async {
        await auth.login(AuthProvider.google, prompt: (_) {});
        expect(auth.email, email);
        expect(auth.isAuthenticated, isTrue);
        expect(buildAuth().email, email);
        expect(buildAuth().isAuthenticated, isTrue);
      });

      group('with custom auth provider', () {
        test(
            '''should set the email when claims are valid and current user exists''',
            () async {
          await auth.login(AuthProvider.microsoft, prompt: (_) {});
          expect(auth.email, email);
          expect(auth.isAuthenticated, isTrue);
          expect(buildAuth().email, email);
          expect(buildAuth().isAuthenticated, isTrue);
        });
      });

      test('throws UserAlreadyLoggedInException if user is authenticated',
          () async {
        writeCredentials();
        auth = buildAuth();

        await expectLater(
          auth.login(AuthProvider.google, prompt: (_) {}),
          throwsA(isA<UserAlreadyLoggedInException>()),
        );

        expect(auth.email, isNotNull);
        expect(auth.isAuthenticated, isTrue);
      });

      test('should not set the email when user does not exist', () async {
        when(() => codePushClient.getCurrentUser())
            .thenAnswer((_) async => null);

        await expectLater(
          auth.login(AuthProvider.google, prompt: (_) {}),
          throwsA(isA<UserNotFoundException>()),
        );

        expect(auth.email, isNull);
        expect(auth.isAuthenticated, isFalse);
      });
    });

    group('loginCI', () {
      setUp(() {
        when(() => platform.environment).thenReturn(
          <String, String>{shorebirdTokenEnvVar: ciToken.toBase64()},
        );
        auth = buildAuth();
      });

      test('returns a CI token and does not set the email or cache credentials',
          () async {
        final token = await auth.loginCI(AuthProvider.google, prompt: (_) {});
        expect(token.authProvider, ciToken.authProvider);
        expect(token.refreshToken, ciToken.refreshToken);
        expect(auth.email, isNull);
        expect(auth.isAuthenticated, isTrue);
        expect(buildAuth().email, isNull);
        expect(buildAuth().isAuthenticated, isTrue);
        when(() => platform.environment).thenReturn({});
        expect(buildAuth().isAuthenticated, isFalse);
      });

      test('throws when user does not exist', () async {
        when(
          () => codePushClient.getCurrentUser(),
        ).thenAnswer((_) async => null);

        await expectLater(
          auth.loginCI(AuthProvider.google, prompt: (_) {}),
          throwsA(isA<UserNotFoundException>()),
        );

        expect(auth.email, isNull);
      });

      group('when credentials are missing a refresh token', () {
        setUp(() {
          accessCredentials = oauth2.AccessCredentials(
            accessToken,
            null,
            scopes,
            idToken: idToken,
          );
        });

        test('throws if credentials are missing a refresh token', () async {
          await expectLater(
            auth.loginCI(AuthProvider.google, prompt: (_) {}),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'toString',
                'Exception: No refresh token found.',
              ),
            ),
          );
        });
      });
    });

    group('logout', () {
      test('clears session and wipes state', () async {
        await auth.login(AuthProvider.google, prompt: (_) {});
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

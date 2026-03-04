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
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_cli_command_runner.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../fakes.dart';
import '../matchers.dart';
import '../mocks.dart';

const googleJwtIssuer = 'https://accounts.google.com';
const microsoftJwtIssuer =
    'https://login.microsoftonline.com/9188040d-6c67-4c5b-b112-36a304b66dad/v2.0';
const shorebirdJwtIssuer = 'https://auth.shorebird.dev';

void main() {
  group('scoped', () {
    test('creates instance with default constructor', () {
      final instance = runScoped(
        () => auth,
        values: {
          authRef,
          httpClientRef.overrideWith(MockHttpClient.new),
          shorebirdEnvRef.overrideWith(ShorebirdEnv.new),
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
    late ShorebirdEnv shorebirdEnv;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      payload = MockJwtPayload();
      jwt = Jwt(
        header: MockJwtHeader(),
        payload: payload,
        signature: 'signature',
      );
      shorebirdEnv = MockShorebirdEnv();
      when(() => shorebirdEnv.jwtIssuer).thenReturn(shorebirdJwtIssuer);
    });

    group('authProvider', () {
      group('when issuer is login.microsoft.online', () {
        setUp(() {
          when(() => payload.iss).thenReturn(microsoftJwtIssuer);
        });

        test('returns AuthProvider.microsoft', () {
          runWithOverrides(() {
            expect(jwt.authProvider, equals(AuthProvider.microsoft));
          });
        });
      });

      group('when issuer is accounts.google.com', () {
        setUp(() {
          when(() => payload.iss).thenReturn(googleJwtIssuer);
        });

        test('returns AuthProvider.google', () {
          runWithOverrides(() {
            expect(jwt.authProvider, equals(AuthProvider.google));
          });
        });
      });

      group('when issuer is auth.shorebird.dev', () {
        setUp(() {
          when(() => payload.iss).thenReturn(shorebirdJwtIssuer);
        });

        test('returns AuthProvider.shorebird', () {
          runWithOverrides(() {
            expect(
              jwt.authProvider,
              equals(AuthProvider.shorebird),
            );
          });
        });
      });

      group('when issuer is unknown', () {
        setUp(() {
          when(() => payload.iss).thenReturn('https://example.com');
        });

        test('throws exception', () {
          runWithOverrides(() {
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
  });

  group(Auth, () {
    const idToken = // cspell:disable-next-line
        '''eyJhbGciOiJIUzI1NiIsImtpZCI6IjEyMzQiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20iLCJhenAiOiI1MjMzMDIyMzMyOTMtZWlhNWFudG0wdGd2ZWsyNDB0NDZvcmN0a3RpYWJyZWsuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJhdWQiOiI1MjMzMDIyMzMyOTMtZWlhNWFudG0wdGd2ZWsyNDB0NDZvcmN0a3RpYWJyZWsuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJzdWIiOiIxMjM0NSIsImhkIjoic2hvcmViaXJkLmRldiIsImVtYWlsIjoidGVzdEBlbWFpbC5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwiaWF0IjoxMjM0LCJleHAiOjY3ODl9.MYbITALvKsGYTYjw1o7AQ0ObkqRWVBSr9cFYJrvA46g''';
    const refreshToken = 'shorebird-token';
    const ciToken = CiToken(
      refreshToken: refreshToken,
      authProvider: AuthProvider.google,
    );
    // cspell:disable-next-line
    const shorebirdIdToken =
        '''eyJhbGciOiJIUzI1NiIsImtpZCI6IjEyMzQiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL2F1dGguc2hvcmViaXJkLmRldiIsImF1ZCI6InNob3JlYmlyZCIsInN1YiI6IjEyMzQ1IiwiZW1haWwiOiJ0ZXN0QGVtYWlsLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJpYXQiOjEyMzQsImV4cCI6Njc4OX0.dGVzdA''';
    const shorebirdCiToken = CiToken(
      refreshToken: 'sb_rt_test',
      authProvider: AuthProvider.shorebird,
    );
    const email = 'test@email.com';
    const user = PrivateUser(id: 42, email: email, jwtIssuer: googleJwtIssuer);
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
    late ShorebirdLogger logger;
    late Auth auth;
    late Platform platform;
    late ShorebirdEnv shorebirdEnv;

    setUpAll(() {
      registerFallbackValue(FakeBaseRequest());
      registerFallbackValue(Uri.parse(''));
    });

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          httpClientRef.overrideWith(() => httpClient),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
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
          obtainAccessCredentials:
              (
                clientId,
                scopes,
                client,
                userPrompt, {
                AuthEndpoints authEndpoints = const GoogleAuthEndpoints(),
              }) async {
                return accessCredentials;
              },
          obtainShorebirdCredentials:
              ({
                required http.Client httpClient,
                required Uri authBaseUrl,
                required void Function(String) userPrompt,
                Duration timeout = const Duration(minutes: 5),
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
      logger = MockShorebirdLogger();
      platform = MockPlatform();
      shorebirdEnv = MockShorebirdEnv();

      when(() => codePushClient.getCurrentUser()).thenAnswer((_) async => user);
      when(() => platform.environment).thenReturn(<String, String>{});
      when(() => shorebirdEnv.jwtIssuer).thenReturn(shorebirdJwtIssuer);
      when(
        () => shorebirdEnv.authServiceUri,
      ).thenReturn(Uri.parse('https://auth.shorebird.dev'));
      when(() => shorebirdEnv.hostedUri).thenReturn(null);

      auth = buildAuth();
    });

    group('AuthenticatedClient', () {
      group('isAuthenticated', () {
        group('when credentials are malformed', () {
          setUp(() {
            File(
              p.join(credentialsDir, 'credentials.json'),
            ).writeAsStringSync('invalid credentials');
            auth = buildAuth();
          });

          test('returns false', () {
            expect(auth.isAuthenticated, isFalse);
          });
        });
      });

      group('token', () {
        test('does not require an onRefreshCredentials callback', () {
          expect(
            () => AuthenticatedClient.token(
              token: ciToken,
              httpClient: httpClient,
              refreshCredentials:
                  (
                    clientId,
                    credentials,
                    client, {
                    AuthEndpoints authEndpoints = const GoogleAuthEndpoints(),
                  }) async => accessCredentials,
            ),
            returnsNormally,
          );
        });

        test(
          'refreshes and uses new token when credentials are expired.',
          () async {
            when(() => httpClient.send(any())).thenAnswer(
              (_) async =>
                  http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
            );

            final onRefreshCredentialsCalls = <oauth2.AccessCredentials>[];

            final client = AuthenticatedClient.token(
              token: ciToken,
              httpClient: httpClient,
              onRefreshCredentials: onRefreshCredentialsCalls.add,
              refreshCredentials:
                  (
                    clientId,
                    credentials,
                    client, {
                    AuthEndpoints authEndpoints = const GoogleAuthEndpoints(),
                  }) async => accessCredentials,
            );

            await runWithOverrides(
              () => client.get(Uri.parse('https://example.com')),
            );

            expect(
              onRefreshCredentialsCalls,
              equals([
                isA<oauth2.AccessCredentials>().having(
                  (c) => c.idToken,
                  'token',
                  idToken,
                ),
              ]),
            );
            final captured = verify(
              () => httpClient.send(captureAny()),
            ).captured;
            expect(captured, hasLength(1));
            final request = captured.first as http.BaseRequest;
            expect(request.headers['Authorization'], equals('Bearer $idToken'));
          },
        );

        group('when refreshing the token fails', () {
          late AuthenticatedClient client;
          setUp(() {
            when(() => httpClient.send(any())).thenAnswer(
              (_) async => http.StreamedResponse(
                const Stream.empty(),
                HttpStatus.badRequest,
              ),
            );

            final onRefreshCredentialsCalls = <oauth2.AccessCredentials>[];

            client = AuthenticatedClient.token(
              token: ciToken,
              httpClient: httpClient,
              onRefreshCredentials: onRefreshCredentialsCalls.add,
              refreshCredentials:
                  (
                    clientId,
                    credentials,
                    client, {
                    AuthEndpoints authEndpoints = const GoogleAuthEndpoints(),
                  }) async => throw Exception('error.'),
            );
          });

          test('exits and logs correctly', () async {
            await expectLater(
              () => runWithOverrides(
                () => client.get(Uri.parse('https://example.com')),
              ),
              exitsWithCode(ExitCode.software),
            );
            verify(
              () => logger.err('Failed to refresh credentials.'),
            ).called(1);
            verify(
              () => logger.info(
                '''Try logging out with ${lightBlue.wrap('shorebird logout')} and logging in again.''',
              ),
            ).called(1);
            verify(() => logger.detail('Exception: error.')).called(1);
          });
        });

        test('uses valid token when credentials valid.', () async {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async =>
                http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
          );
          final onRefreshCredentialsCalls = <oauth2.AccessCredentials>[];
          final client = AuthenticatedClient.token(
            token: ciToken,
            httpClient: httpClient,
            onRefreshCredentials: onRefreshCredentialsCalls.add,
            refreshCredentials:
                (
                  clientId,
                  credentials,
                  client, {
                  AuthEndpoints authEndpoints = const GoogleAuthEndpoints(),
                }) async => accessCredentials,
          );

          await runWithOverrides(() async {
            await client.get(Uri.parse('https://example.com'));
            await client.get(Uri.parse('https://example.com'));
          });

          expect(onRefreshCredentialsCalls.length, equals(1));
          final captured = verify(() => httpClient.send(captureAny())).captured;
          expect(captured, hasLength(2));
          var request = captured.first as http.BaseRequest;
          expect(request.headers['Authorization'], equals('Bearer $idToken'));
          request = captured.last as http.BaseRequest;
          expect(request.headers['Authorization'], equals('Bearer $idToken'));
        });

        group('when token is Shorebird', () {
          test(
            'refreshes via Shorebird and uses new token',
            () async {
              when(() => httpClient.send(any())).thenAnswer(
                (_) async => http.StreamedResponse(
                  const Stream.empty(),
                  HttpStatus.ok,
                ),
              );
              when(
                () => httpClient.post(
                  any(),
                  headers: any(named: 'headers'),
                  body: any(named: 'body'),
                ),
              ).thenAnswer(
                (_) async => http.Response(
                  jsonEncode({
                    'access_token': shorebirdIdToken,
                    'refresh_token': 'sb_rt_new',
                    'token_type': 'Bearer',
                    'expires_in': 900,
                  }),
                  HttpStatus.ok,
                ),
              );

              final onRefreshCredentialsCalls = <oauth2.AccessCredentials>[];
              final client = AuthenticatedClient.token(
                token: shorebirdCiToken,
                httpClient: httpClient,
                authServiceUri: Uri.parse('https://auth.shorebird.dev'),
                onRefreshCredentials: onRefreshCredentialsCalls.add,
              );

              await runWithOverrides(
                () => client.get(
                  Uri.parse('https://example.com'),
                ),
              );

              expect(onRefreshCredentialsCalls, hasLength(1));
              expect(
                onRefreshCredentialsCalls.first.refreshToken,
                equals('sb_rt_new'),
              );
              final captured = verify(
                () => httpClient.send(captureAny()),
              ).captured;
              expect(captured, hasLength(1));
              final request = captured.first as http.BaseRequest;
              expect(
                request.headers['Authorization'],
                equals('Bearer $shorebirdIdToken'),
              );
              verify(
                () => httpClient.post(
                  Uri.parse('https://auth.shorebird.dev/token'),
                  headers: any(named: 'headers'),
                  body: any(named: 'body'),
                ),
              ).called(1);
            },
          );

          group('when Shorebird refresh fails', () {
            late AuthenticatedClient client;
            setUp(() {
              when(
                () => httpClient.post(
                  any(),
                  headers: any(named: 'headers'),
                  body: any(named: 'body'),
                ),
              ).thenThrow(Exception('refresh failed'));

              client = AuthenticatedClient.token(
                token: shorebirdCiToken,
                httpClient: httpClient,
                authServiceUri: Uri.parse('https://auth.shorebird.dev'),
              );
            });

            test('exits and logs correctly', () async {
              await expectLater(
                () => runWithOverrides(
                  () => client.get(
                    Uri.parse('https://example.com'),
                  ),
                ),
                exitsWithCode(ExitCode.software),
              );
              verify(
                () => logger.err(
                  'Failed to refresh credentials.',
                ),
              ).called(1);
              verify(
                () => logger.info(
                  '''Try logging out with ${lightBlue.wrap('shorebird logout')} and logging in again.''',
                ),
              ).called(1);
              verify(
                () => logger.detail('Exception: refresh failed'),
              ).called(1);
            });
          });
        });
      });

      group('credentials', () {
        test(
          'refreshes and uses new token when credentials are expired.',
          () async {
            when(() => httpClient.send(any())).thenAnswer(
              (_) async =>
                  http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
            );

            const expiredIdToken = // cspell:disable-next-line
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
              refreshCredentials:
                  (
                    clientId,
                    credentials,
                    client, {
                    AuthEndpoints authEndpoints = const GoogleAuthEndpoints(),
                  }) async => accessCredentials,
            );

            await runWithOverrides(
              () => client.get(Uri.parse('https://example.com')),
            );

            expect(
              onRefreshCredentialsCalls,
              equals([
                isA<oauth2.AccessCredentials>().having(
                  (c) => c.idToken,
                  'token',
                  idToken,
                ),
              ]),
            );
            final captured = verify(
              () => httpClient.send(captureAny()),
            ).captured;
            expect(captured, hasLength(1));
            final request = captured.first as http.BaseRequest;
            expect(request.headers['Authorization'], equals('Bearer $idToken'));
          },
        );

        group('when refreshing the token fails', () {
          late AuthenticatedClient client;
          setUp(() {
            when(() => httpClient.send(any())).thenAnswer(
              (_) async => http.StreamedResponse(
                const Stream.empty(),
                HttpStatus.badRequest,
              ),
            );

            const expiredIdToken = // cspell:disable-next-line
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

            client = AuthenticatedClient.credentials(
              credentials: expiredCredentials,
              httpClient: httpClient,
              onRefreshCredentials: onRefreshCredentialsCalls.add,
              refreshCredentials:
                  (
                    clientId,
                    credentials,
                    client, {
                    AuthEndpoints authEndpoints = const GoogleAuthEndpoints(),
                  }) async => throw Exception('error.'),
            );
          });

          test('exits and logs correctly', () async {
            await expectLater(
              () => runWithOverrides(
                () => client.get(Uri.parse('https://example.com')),
              ),
              exitsWithCode(ExitCode.software),
            );
            verify(
              () => logger.err('Failed to refresh credentials.'),
            ).called(1);
            verify(
              () => logger.info(
                '''Try logging out with ${lightBlue.wrap('shorebird logout')} and logging in again.''',
              ),
            ).called(1);
            verify(() => logger.detail('Exception: error.')).called(1);
          });
        });

        test('uses valid token when credentials valid.', () async {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async =>
                http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
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

        group('when expired credentials have Shorebird issuer', () {
          test(
            'refreshes via Shorebird and uses new token',
            () async {
              when(() => httpClient.send(any())).thenAnswer(
                (_) async => http.StreamedResponse(
                  const Stream.empty(),
                  HttpStatus.ok,
                ),
              );
              when(
                () => httpClient.post(
                  any(),
                  headers: any(named: 'headers'),
                  body: any(named: 'body'),
                ),
              ).thenAnswer(
                (_) async => http.Response(
                  jsonEncode({
                    'access_token': shorebirdIdToken,
                    'refresh_token': 'sb_rt_rotated',
                    'token_type': 'Bearer',
                    'expires_in': 900,
                  }),
                  HttpStatus.ok,
                ),
              );

              final onRefreshCredentialsCalls = <oauth2.AccessCredentials>[];
              final expiredShorebirdCredentials = oauth2.AccessCredentials(
                oauth2.AccessToken(
                  'Bearer',
                  'accessToken',
                  DateTime.now().subtract(const Duration(minutes: 1)).toUtc(),
                ),
                'sb_rt_old',
                [],
                idToken: shorebirdIdToken,
              );

              final client = AuthenticatedClient.credentials(
                credentials: expiredShorebirdCredentials,
                httpClient: httpClient,
                authServiceUri: Uri.parse('https://auth.shorebird.dev'),
                onRefreshCredentials: onRefreshCredentialsCalls.add,
              );

              await runWithOverrides(
                () => client.get(
                  Uri.parse('https://example.com'),
                ),
              );

              expect(onRefreshCredentialsCalls, hasLength(1));
              expect(
                onRefreshCredentialsCalls.first.refreshToken,
                equals('sb_rt_rotated'),
              );
              final captured = verify(
                () => httpClient.send(captureAny()),
              ).captured;
              expect(captured, hasLength(1));
              final request = captured.first as http.BaseRequest;
              expect(
                request.headers['Authorization'],
                equals('Bearer $shorebirdIdToken'),
              );
              verify(
                () => httpClient.post(
                  Uri.parse('https://auth.shorebird.dev/token'),
                  headers: any(named: 'headers'),
                  body: any(named: 'body'),
                ),
              ).called(1);
            },
          );
        });

        group('when Shorebird credential refresh fails', () {
          late AuthenticatedClient client;
          setUp(() {
            when(
              () => httpClient.post(
                any(),
                headers: any(named: 'headers'),
                body: any(named: 'body'),
              ),
            ).thenThrow(Exception('refresh failed'));

            final expiredShorebirdCredentials = oauth2.AccessCredentials(
              oauth2.AccessToken(
                'Bearer',
                'accessToken',
                DateTime.now().subtract(const Duration(minutes: 1)).toUtc(),
              ),
              'sb_rt_old',
              [],
              idToken: shorebirdIdToken,
            );

            client = AuthenticatedClient.credentials(
              credentials: expiredShorebirdCredentials,
              httpClient: httpClient,
              authServiceUri: Uri.parse('https://auth.shorebird.dev'),
            );
          });

          test('exits and logs correctly', () async {
            await expectLater(
              () => runWithOverrides(
                () => client.get(
                  Uri.parse('https://example.com'),
                ),
              ),
              exitsWithCode(ExitCode.software),
            );
            verify(
              () => logger.err(
                'Failed to refresh credentials.',
              ),
            ).called(1);
            verify(
              () => logger.info(
                '''Try logging out with ${lightBlue.wrap('shorebird logout')} and logging in again.''',
              ),
            ).called(1);
            verify(
              () => logger.detail('Exception: refresh failed'),
            ).called(1);
          });
        });
      });
    });

    group('client', () {
      test('returns an authenticated client '
          'when credentials are present.', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
        );
        await runWithOverrides(
          () => auth.login(AuthProvider.google, prompt: (_) {}),
        );
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
          when(() => platform.environment).thenReturn(<String, String>{
            shorebirdTokenEnvVar: 'not a base64 string',
          });
        });

        test(
          'logs and throws error when token string is not valid base64',
          () async {
            expect(buildAuth, throwsA(isFormatException));
            verify(
              () => logger.detail('[env] $shorebirdTokenEnvVar detected'),
            ).called(1);
            verify(
              () => logger.err(
                '''
Failed to parse CI token from environment. This likely means that your CI token is incorrectly formatted.

Please regenerate using `shorebird login:ci`, update the $shorebirdTokenEnvVar environment variable, and try again.''',
              ),
            ).called(1);
            verifyNever(
              () => logger.detail('[env] $shorebirdTokenEnvVar parsed'),
            );
          },
        );
      });

      group('when token has leading or trailing spaces and newlines', () {
        setUp(() {
          when(() => platform.environment).thenReturn(<String, String>{
            shorebirdTokenEnvVar:
                '''
    ${ciToken.toBase64()}  
              
''',
          });
        });

        test('trims string', () {
          auth = buildAuth();
          final client = auth.client;
          expect(client, isA<http.Client>());
          expect(client, isA<AuthenticatedClient>());
        });
      });

      test('returns an authenticated client '
          'when a token and token provider is present.', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async =>
              http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
        );
        when(() => platform.environment).thenReturn(<String, String>{
          shorebirdTokenEnvVar: ciToken.toBase64(),
        });
        auth = buildAuth();
        final client = auth.client;
        expect(client, isA<http.Client>());
        expect(client, isA<AuthenticatedClient>());
        verify(
          () => logger.detail('[env] $shorebirdTokenEnvVar detected'),
        ).called(1);
        verify(
          () => logger.detail('[env] $shorebirdTokenEnvVar parsed'),
        ).called(1);
      });

      test(
        'returns a plain http client when credentials are not present.',
        () async {
          final client = auth.client;
          expect(client, isA<http.Client>());
          expect(client, isNot(isA<oauth2.AutoRefreshingAuthClient>()));
        },
      );
    });

    group('login', () {
      test(
        'should set the email when claims are valid and current user exists',
        () async {
          await runWithOverrides(
            () => auth.login(AuthProvider.google, prompt: (_) {}),
          );
          expect(auth.email, email);
          expect(auth.isAuthenticated, isTrue);
          expect(buildAuth().email, email);
          expect(buildAuth().isAuthenticated, isTrue);
        },
      );

      group('with custom auth provider', () {
        test(
          '''should set the email when claims are valid and current user exists''',
          () async {
            await runWithOverrides(
              () => auth.login(AuthProvider.microsoft, prompt: (_) {}),
            );
            expect(auth.email, email);
            expect(auth.isAuthenticated, isTrue);
            expect(buildAuth().email, email);
            expect(buildAuth().isAuthenticated, isTrue);
          },
        );
      });

      group('with Shorebird auth provider', () {
        test(
          'should set the email when login succeeds',
          () async {
            await runWithOverrides(
              () => auth.login(
                AuthProvider.shorebird,
                prompt: (_) {},
              ),
            );
            expect(auth.email, email);
            expect(auth.isAuthenticated, isTrue);
            expect(buildAuth().email, email);
            expect(buildAuth().isAuthenticated, isTrue);
          },
        );
      });

      test(
        'throws UserAlreadyLoggedInException if user is authenticated',
        () async {
          writeCredentials();
          auth = buildAuth();

          await expectLater(
            runWithOverrides(
              () => auth.login(AuthProvider.google, prompt: (_) {}),
            ),
            throwsA(isA<UserAlreadyLoggedInException>()),
          );

          expect(auth.email, isNotNull);
          expect(auth.isAuthenticated, isTrue);
        },
      );

      group('when login credentials are corrupted', () {
        setUp(() {
          accessCredentials = oauth2.AccessCredentials(
            accessToken,
            refreshToken,
            scopes,
            idToken: 'not a valid jwt',
          );
          writeCredentials();
          auth = buildAuth();
        });

        test('proceeds with login', () async {
          expect(auth.email, isNull);
          await runWithOverrides(
            () => auth.login(AuthProvider.google, prompt: (_) {}),
          );
          expect(auth.email, equals(email));
          expect(auth.isAuthenticated, isTrue);
        });
      });

      test('should not set the email when user does not exist', () async {
        when(
          () => codePushClient.getCurrentUser(),
        ).thenAnswer((_) async => null);

        await expectLater(
          runWithOverrides(
            () => auth.login(AuthProvider.google, prompt: (_) {}),
          ),
          throwsA(isA<UserNotFoundException>()),
        );

        expect(auth.email, isNull);
        expect(auth.isAuthenticated, isFalse);
      });
    });

    group('loginCI', () {
      setUp(() {
        when(() => platform.environment).thenReturn(<String, String>{
          shorebirdTokenEnvVar: ciToken.toBase64(),
        });
        auth = buildAuth();
      });

      test(
        'returns a CI token and does not set the email or cache credentials',
        () async {
          final token = await runWithOverrides(
            () => auth.loginCI(AuthProvider.google, prompt: (_) {}),
          );
          expect(token.authProvider, ciToken.authProvider);
          expect(token.refreshToken, ciToken.refreshToken);
          expect(auth.email, isNull);
          expect(auth.isAuthenticated, isTrue);
          expect(buildAuth().email, isNull);
          expect(buildAuth().isAuthenticated, isTrue);
          when(() => platform.environment).thenReturn({});
          expect(buildAuth().isAuthenticated, isFalse);
        },
      );

      group('with Shorebird auth provider', () {
        test(
          'returns a CI token with Shorebird provider',
          () async {
            final token = await runWithOverrides(
              () => auth.loginCI(
                AuthProvider.shorebird,
                prompt: (_) {},
              ),
            );
            expect(
              token.authProvider,
              AuthProvider.shorebird,
            );
            expect(token.refreshToken, refreshToken);
          },
        );
      });

      test('throws when user does not exist', () async {
        when(
          () => codePushClient.getCurrentUser(),
        ).thenAnswer((_) async => null);

        await expectLater(
          runWithOverrides(
            () => auth.loginCI(AuthProvider.google, prompt: (_) {}),
          ),
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
            runWithOverrides(
              () => auth.loginCI(AuthProvider.google, prompt: (_) {}),
            ),
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
        await runWithOverrides(
          () => auth.login(AuthProvider.google, prompt: (_) {}),
        );
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

  group('OauthValues', () {
    group('clientId', () {
      test('throws UnsupportedError for shorebird', () {
        expect(
          () => AuthProvider.shorebird.clientId,
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'message',
              'Shorebird auth does not use a client ID',
            ),
          ),
        );
      });
    });

    group('authEndpoints', () {
      test('returns ShorebirdAuthEndpoints for shorebird', () {
        late ShorebirdEnv shorebirdEnv;
        runScoped(
          () {
            shorebirdEnv = MockShorebirdEnv();
            when(
              () => shorebirdEnv.authServiceUri,
            ).thenReturn(Uri.parse('https://auth.shorebird.dev'));
            expect(
              AuthProvider.shorebird.authEndpoints,
              isA<AuthEndpoints>(),
            );
          },
          values: {
            shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          },
        );
      });
    });
  });

  group('AuthenticatedClient', () {
    group(
      'when Shorebird token refresh is attempted without authServiceUri',
      () {
        late http.Client httpClient;
        late ShorebirdLogger logger;
        late Platform platform;
        late ShorebirdEnv shorebirdEnv;

        const shorebirdCiToken = CiToken(
          refreshToken: 'sb_rt_test',
          authProvider: AuthProvider.shorebird,
        );

        setUpAll(() {
          registerFallbackValue(FakeBaseRequest());
        });

        setUp(() {
          httpClient = MockHttpClient();
          logger = MockShorebirdLogger();
          platform = MockPlatform();
          shorebirdEnv = MockShorebirdEnv();
          when(() => platform.environment).thenReturn(<String, String>{});
          when(() => shorebirdEnv.jwtIssuer).thenReturn(shorebirdJwtIssuer);
        });

        test('throws StateError', () async {
          final client = AuthenticatedClient.token(
            token: shorebirdCiToken,
            httpClient: httpClient,
          );

          await expectLater(
            () => runScoped(
              () => client.get(Uri.parse('https://example.com')),
              values: {
                loggerRef.overrideWith(() => logger),
                platformRef.overrideWith(() => platform),
                shorebirdEnvRef.overrideWith(() => shorebirdEnv),
              },
            ),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('authServiceUri must be provided'),
              ),
            ),
          );
        });
      },
    );
  });
}

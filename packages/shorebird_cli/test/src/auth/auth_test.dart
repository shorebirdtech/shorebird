import 'dart:convert';
import 'dart:io' hide Platform;

import 'package:cli_util/cli_util.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as oauth2;
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/shorebird_oauth.dart';
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
        p.join(BaseDirectories(executableName).configHome, 'credentials.json'),
      );
    });
  });

  group('JwtClaims', () {
    group('email', () {
      test('returns null when the access token is not a valid jwt', () {
        final credentials = oauth2.AccessCredentials(
          oauth2.AccessToken(
            'Bearer',
            'not a valid jwt',
            DateTime.now().add(const Duration(minutes: 10)).toUtc(),
          ),
          '',
          [],
        );

        expect(credentials.email, isNull);
      });
    });
  });

  group(Auth, () {
    // Issued by accounts.google.com, as stored by CLI versions that supported
    // Google login.
    const googleIdToken = // cspell:disable-next-line
        '''eyJhbGciOiJIUzI1NiIsImtpZCI6IjEyMzQiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20iLCJhenAiOiI1MjMzMDIyMzMyOTMtZWlhNWFudG0wdGd2ZWsyNDB0NDZvcmN0a3RpYWJyZWsuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJhdWQiOiI1MjMzMDIyMzMyOTMtZWlhNWFudG0wdGd2ZWsyNDB0NDZvcmN0a3RpYWJyZWsuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJzdWIiOiIxMjM0NSIsImhkIjoic2hvcmViaXJkLmRldiIsImVtYWlsIjoidGVzdEBlbWFpbC5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwiaWF0IjoxMjM0LCJleHAiOjY3ODl9.MYbITALvKsGYTYjw1o7AQ0ObkqRWVBSr9cFYJrvA46g''';
    const refreshToken = 'sb_rt_test';
    // Decoded payload:
    // {
    //   "iss": "https://auth.shorebird.dev",
    //   "aud": "shorebird",
    //   "sub": "12345",
    //   "email": "test@email.com",
    //   "email_verified": true,
    //   "iat": 1234,
    //   "exp": 6789
    // }
    // cspell:disable-next-line
    const shorebirdAccessToken =
        '''eyJhbGciOiJIUzI1NiIsImtpZCI6IjEyMzQiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL2F1dGguc2hvcmViaXJkLmRldiIsImF1ZCI6InNob3JlYmlyZCIsInN1YiI6IjEyMzQ1IiwiZW1haWwiOiJ0ZXN0QGVtYWlsLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJpYXQiOjEyMzQsImV4cCI6Njc4OX0.dGVzdA''';
    const email = 'test@email.com';
    const user = PrivateUser(
      id: 42,
      email: email,
      jwtIssuer: shorebirdJwtIssuer,
    );
    const scopes = <String>[];
    final accessToken = oauth2.AccessToken(
      'Bearer',
      shorebirdAccessToken,
      DateTime.now().add(const Duration(minutes: 10)).toUtc(),
    );

    late oauth2.AccessCredentials accessCredentials;
    final deviceAuthorization = DeviceAuthorization(
      deviceCode: 'device-code',
      userCode: 'BEST-CAKE',
      verificationUri: Uri.parse('https://auth.shorebird.dev/device'),
      expiresIn: const Duration(minutes: 15),
      interval: const Duration(seconds: 5),
    );
    late String credentialsDir;
    late http.Client httpClient;
    late CodePushClient codePushClient;
    late ShorebirdLogger logger;
    late Auth auth;
    late TestNativePlatform platform;
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
          obtainCredentialsViaLoopbackLogin:
              ({
                required http.Client httpClient,
                required Uri authBaseUrl,
                required void Function(String) userPrompt,
                Duration timeout = const Duration(minutes: 5),
              }) async {
                return accessCredentials;
              },
          obtainCredentialsViaDeviceLogin:
              ({
                required http.Client httpClient,
                required Uri authBaseUrl,
                required void Function(DeviceAuthorization) userPrompt,
              }) async {
                userPrompt(deviceAuthorization);
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

    void answerRefreshWith(http.Response response) {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => response);
    }

    setUp(() {
      accessCredentials = oauth2.AccessCredentials(
        accessToken,
        refreshToken,
        scopes,
      );
      credentialsDir = Directory.systemTemp.createTempSync().path;
      httpClient = MockHttpClient();
      codePushClient = MockCodePushClient();
      logger = MockShorebirdLogger();
      platform = TestNativePlatform(environment: {});
      shorebirdEnv = MockShorebirdEnv();

      when(() => codePushClient.getCurrentUser()).thenAnswer((_) async => user);
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

        group('when stored credentials were issued by Google', () {
          setUp(() {
            accessCredentials = oauth2.AccessCredentials(
              oauth2.AccessToken(
                'Bearer',
                'ya29.google-access-token',
                DateTime.now().add(const Duration(minutes: 10)).toUtc(),
              ),
              refreshToken,
              scopes,
              idToken: googleIdToken,
            );
            writeCredentials();
            auth = buildAuth();
          });

          test('returns false and tells the user to log in again', () {
            expect(auth.isAuthenticated, isFalse);
            expect(auth.email, isNull);
            expect(auth.client, same(httpClient));
            verify(
              () => logger.warn(
                '''Your stored credentials are no longer valid. Run ${lightCyan.wrap('shorebird login')} to sign in again.''',
              ),
            ).called(1);
          });

          test('allows logging in again', () async {
            accessCredentials = oauth2.AccessCredentials(
              accessToken,
              refreshToken,
              scopes,
            );
            await runWithOverrides(() => auth.login(prompt: (_) {}));
            expect(auth.isAuthenticated, isTrue);
            expect(buildAuth().email, equals(email));
          });
        });

        group('when stored credentials also carry the token as idToken', () {
          // How CLI versions before the access token was sent as itself
          // wrote credentials.json.
          setUp(() {
            accessCredentials = oauth2.AccessCredentials(
              accessToken,
              refreshToken,
              scopes,
              idToken: shorebirdAccessToken,
            );
            writeCredentials();
            auth = buildAuth();
          });

          test('loads them', () {
            expect(auth.isAuthenticated, isTrue);
            expect(auth.email, equals(email));
          });
        });

        group('when the stored access token is not a JWT', () {
          setUp(() {
            accessCredentials = oauth2.AccessCredentials(
              oauth2.AccessToken(
                'Bearer',
                'opaque',
                DateTime.now().add(const Duration(minutes: 10)).toUtc(),
              ),
              refreshToken,
              scopes,
            );
            writeCredentials();
            auth = buildAuth();
          });

          test('returns false', () {
            expect(auth.isAuthenticated, isFalse);
            verify(() => logger.warn(any())).called(1);
          });
        });
      });

      group('credentials', () {
        test('uses valid token when credentials valid.', () async {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async =>
                http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
          );
          final onRefreshCredentialsCalls = <oauth2.AccessCredentials>[];
          final client = AuthenticatedClient(
            credentials: accessCredentials,
            httpClient: httpClient,
            authServiceUri: Uri.parse('https://auth.shorebird.dev'),
            onRefreshCredentials: onRefreshCredentialsCalls.add,
          );

          await runWithOverrides(
            () => client.get(Uri.parse('https://example.com')),
          );

          expect(onRefreshCredentialsCalls, isEmpty);
          final captured = verify(() => httpClient.send(captureAny())).captured;
          expect(captured, hasLength(1));
          final request = captured.first as http.BaseRequest;
          expect(
            request.headers['Authorization'],
            equals('Bearer $shorebirdAccessToken'),
          );
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
                    'access_token': shorebirdAccessToken,
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
              );

              final client = AuthenticatedClient(
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
                equals('Bearer $shorebirdAccessToken'),
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
            );

            client = AuthenticatedClient(
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
          () => auth.login(prompt: (_) {}),
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
        expect(
          request.headers['Authorization'],
          equals('Bearer $shorebirdAccessToken'),
        );
      });

      group('when SHOREBIRD_TOKEN is an API key', () {
        setUp(() {
          platform = platform.copyWith(
            environment: {
              shorebirdTokenEnvVar: 'sb_api_abc123',
            },
          );
        });

        test('parses as API key and sets isAuthenticated', () {
          auth = buildAuth();
          expect(auth.isAuthenticated, isTrue);
          expect(auth.email, isNull);
          verify(
            () => logger.detail('[env] $shorebirdTokenEnvVar detected'),
          ).called(1);
          verify(
            () => logger.detail(
              '[env] $shorebirdTokenEnvVar parsed as API key',
            ),
          ).called(1);
        });

        test('trims whitespace from API key', () {
          platform = platform.copyWith(
            environment: {
              shorebirdTokenEnvVar: '  sb_api_abc123  \n',
            },
          );
          auth = buildAuth();
          expect(auth.isAuthenticated, isTrue);
        });

        test('returns an ApiKeyClient from client getter', () {
          auth = buildAuth();
          final client = auth.client;
          expect(client, isA<ApiKeyClient>());
        });

        test('ApiKeyClient sends correct Authorization header', () async {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async =>
                http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
          );
          auth = buildAuth();
          final client = auth.client;

          await runWithOverrides(
            () => client.get(Uri.parse('https://example.com')),
          );

          final captured = verify(() => httpClient.send(captureAny())).captured;
          expect(captured, hasLength(1));
          final request = captured.first as http.BaseRequest;
          expect(
            request.headers['Authorization'],
            equals('Bearer sb_api_abc123'),
          );
        });

        test('takes priority over credentials file', () {
          writeCredentials();
          auth = buildAuth();
          expect(auth.isAuthenticated, isTrue);
          expect(auth.email, isNull);
          expect(auth.client, isA<ApiKeyClient>());
        });
      });

      group('when SHOREBIRD_TOKEN is not an API key', () {
        setUp(() {
          platform = platform.copyWith(
            environment: {
              // A legacy `shorebird login:ci` token.
              shorebirdTokenEnvVar: base64Encode(
                utf8.encode(
                  jsonEncode({
                    'refresh_token': 'refresh',
                    'auth_provider': 'google',
                  }),
                ),
              ),
            },
          );
        });

        test('logs an error and exits', () {
          expect(buildAuth, exitsWithCode(ExitCode.config));
          verify(
            () => logger.detail('[env] $shorebirdTokenEnvVar detected'),
          ).called(1);
          verify(
            () => logger.err(
              '$shorebirdTokenEnvVar is not a Shorebird API key '
              '(API keys start with sb_api_).',
            ),
          ).called(1);
          verify(
            () => logger.info(
              any(
                that: contains(
                  'CI tokens from `shorebird login:ci` are no longer '
                  'supported.',
                ),
              ),
            ),
          ).called(1);
        });
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

    group('hasValidCredentials', () {
      group('when there are no credentials', () {
        test('returns false', () async {
          expect(await runWithOverrides(auth.hasValidCredentials), isFalse);
        });
      });

      group('when authenticated via API key', () {
        setUp(() {
          platform = platform.copyWith(
            environment: {
              shorebirdTokenEnvVar: 'sb_api_abc123',
            },
          );
          auth = buildAuth();
        });

        test('returns true without refreshing', () async {
          expect(await runWithOverrides(auth.hasValidCredentials), isTrue);
        });
      });

      group('when stored credentials are malformed', () {
        setUp(() {
          accessCredentials = oauth2.AccessCredentials(
            oauth2.AccessToken(
              'Bearer',
              'not a valid jwt',
              DateTime.now().add(const Duration(minutes: 10)).toUtc(),
            ),
            refreshToken,
            scopes,
          );
          writeCredentials();
          auth = buildAuth();
        });

        test('returns false', () async {
          expect(await runWithOverrides(auth.hasValidCredentials), isFalse);
        });
      });

      group('when stored credentials can be refreshed', () {
        setUp(() {
          writeCredentials();
          answerRefreshWith(
            http.Response(
              jsonEncode({
                'access_token': shorebirdAccessToken,
                'refresh_token': 'sb_rt_rotated',
                'token_type': 'Bearer',
                'expires_in': 900,
              }),
              HttpStatus.ok,
            ),
          );
          auth = buildAuth();
        });

        test('returns true and persists the refreshed credentials', () async {
          expect(await runWithOverrides(auth.hasValidCredentials), isTrue);
          expect(auth.email, equals(email));
          expect(File(auth.credentialsFilePath).existsSync(), isTrue);
        });
      });

      // An expired or revoked refresh token comes back `invalid_grant`
      // (RFC 6749 section 5.2).
      group('when the refresh is refused', () {
        setUp(writeCredentials);

        for (final status in [HttpStatus.badRequest, HttpStatus.unauthorized]) {
          test('returns false for a $status invalid_grant', () async {
            answerRefreshWith(
              http.Response(jsonEncode({'error': 'invalid_grant'}), status),
            );
            auth = buildAuth();
            expect(await runWithOverrides(auth.hasValidCredentials), isFalse);
          });
        }
      });

      // A 4xx that is not `invalid_grant` says nothing about the credentials.
      group('when the auth service refuses the request itself', () {
        setUp(writeCredentials);

        Future<void> expectRethrows(http.Response response) async {
          answerRefreshWith(response);
          auth = buildAuth();
          await expectLater(
            runWithOverrides(auth.hasValidCredentials),
            throwsA(
              isA<ShorebirdAuthException>().having(
                (e) => e.statusCode,
                'statusCode',
                response.statusCode,
              ),
            ),
          );
        }

        test('rethrows a 429 rate_limited', () async {
          await expectRethrows(
            http.Response(
              jsonEncode({'error': 'rate_limited'}),
              HttpStatus.tooManyRequests,
            ),
          );
        });

        test('rethrows a 400 invalid_request', () async {
          await expectRethrows(
            http.Response(
              jsonEncode({'error': 'invalid_request'}),
              HttpStatus.badRequest,
            ),
          );
        });

        test('rethrows a 4xx that is not an OAuth error response', () async {
          await expectRethrows(
            http.Response('Unauthorized', HttpStatus.unauthorized),
          );
        });
      });

      // Answering false here would log the user out over a bad connection,
      // which is not what a failure to reach the auth service means.
      group('when the auth service cannot answer', () {
        setUp(writeCredentials);

        test('rethrows a 5xx', () async {
          answerRefreshWith(http.Response('bad gateway', 502));
          auth = buildAuth();
          await expectLater(
            runWithOverrides(auth.hasValidCredentials),
            throwsA(
              isA<ShorebirdAuthException>().having(
                (e) => e.statusCode,
                'statusCode',
                502,
              ),
            ),
          );
        });

        test('rethrows a network failure', () async {
          when(
            () => httpClient.post(
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          ).thenThrow(const SocketException('no route to host'));
          auth = buildAuth();
          await expectLater(
            runWithOverrides(auth.hasValidCredentials),
            throwsA(isA<SocketException>()),
          );
        });
      });
    });

    group('login', () {
      test(
        'should set the email when claims are valid and current user exists',
        () async {
          await runWithOverrides(
            () => auth.login(prompt: (_) {}),
          );
          expect(auth.email, email);
          expect(auth.isAuthenticated, isTrue);
          expect(buildAuth().email, email);
          expect(buildAuth().isAuthenticated, isTrue);
        },
      );

      test(
        'throws UserAlreadyLoggedInException if user is authenticated',
        () async {
          writeCredentials();
          auth = buildAuth();

          await expectLater(
            runWithOverrides(
              () => auth.login(prompt: (_) {}),
            ),
            throwsA(isA<UserAlreadyLoggedInException>()),
          );

          expect(auth.email, isNotNull);
          expect(auth.isAuthenticated, isTrue);
        },
      );

      test(
        'throws UserAlreadyLoggedInException when authenticated via API key',
        () async {
          platform = platform.copyWith(
            environment: {
              shorebirdTokenEnvVar: 'sb_api_abc123',
            },
          );
          auth = buildAuth();

          await expectLater(
            runWithOverrides(
              () => auth.login(prompt: (_) {}),
            ),
            throwsA(
              isA<UserAlreadyLoggedInException>().having(
                (e) => e.email,
                'email',
                isNull,
              ),
            ),
          );
        },
      );

      group('when login credentials are corrupted', () {
        setUp(() {
          accessCredentials = oauth2.AccessCredentials(
            oauth2.AccessToken(
              'Bearer',
              'not a valid jwt',
              DateTime.now().add(const Duration(minutes: 10)).toUtc(),
            ),
            refreshToken,
            scopes,
          );
          writeCredentials();
          auth = buildAuth();
        });

        test('proceeds with login', () async {
          expect(auth.email, isNull);
          await runWithOverrides(
            () => auth.login(prompt: (_) {}),
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
            () => auth.login(prompt: (_) {}),
          ),
          throwsA(isA<UserNotFoundException>()),
        );

        expect(auth.email, isNull);
        expect(auth.isAuthenticated, isFalse);
      });
    });

    group('loginWithDeviceCode', () {
      test('prompts with the device code and stores credentials', () async {
        final prompts = <DeviceAuthorization>[];
        await runWithOverrides(
          () => auth.loginWithDeviceCode(prompt: prompts.add),
        );

        expect(prompts, equals([deviceAuthorization]));
        expect(auth.email, email);
        expect(auth.isAuthenticated, isTrue);
        // Stored where the loopback login stores them, so a fresh Auth
        // loads, refreshes and revokes them the same way.
        final reloaded = buildAuth();
        expect(reloaded.email, email);
        expect(reloaded.isAuthenticated, isTrue);
        expect(
          jsonDecode(File(auth.credentialsFilePath).readAsStringSync()),
          equals(jsonDecode(jsonEncode(accessCredentials.toJson()))),
        );
      });

      test('throws UserAlreadyLoggedInException if user is authenticated', () {
        writeCredentials();
        auth = buildAuth();

        expect(
          runWithOverrides(() => auth.loginWithDeviceCode(prompt: (_) {})),
          throwsA(isA<UserAlreadyLoggedInException>()),
        );
      });

      test('throws UserNotFoundException when user does not exist', () async {
        when(
          () => codePushClient.getCurrentUser(),
        ).thenAnswer((_) async => null);

        await expectLater(
          runWithOverrides(() => auth.loginWithDeviceCode(prompt: (_) {})),
          throwsA(isA<UserNotFoundException>()),
        );
        expect(auth.isAuthenticated, isFalse);
      });
    });

    group('logout', () {
      void stubRevocation(Future<http.Response> Function() answer) {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) => answer());
      }

      setUp(() {
        stubRevocation(() async => http.Response('', HttpStatus.ok));
      });

      test('clears session and wipes state', () async {
        await runWithOverrides(
          () => auth.login(prompt: (_) {}),
        );
        expect(auth.email, email);
        expect(auth.isAuthenticated, isTrue);

        await runWithOverrides(() => auth.logout());
        expect(auth.email, isNull);
        expect(auth.isAuthenticated, isFalse);
        expect(buildAuth().email, isNull);
        expect(buildAuth().isAuthenticated, isFalse);
      });

      test('clears credentials file when it exists', () async {
        await runWithOverrides(
          () => auth.login(prompt: (_) {}),
        );
        expect(File(auth.credentialsFilePath).existsSync(), isTrue);

        await runWithOverrides(() => auth.logout());
        expect(File(auth.credentialsFilePath).existsSync(), isFalse);
      });

      group('when authenticated via API key', () {
        setUp(() {
          platform = platform.copyWith(
            environment: {
              shorebirdTokenEnvVar: 'sb_api_abc123',
            },
          );
          auth = buildAuth();
        });

        test('remains authenticated because env var is still set', () async {
          expect(auth.isAuthenticated, isTrue);
          await runWithOverrides(() => auth.logout());
          // _apiKey is not cleared by _clearCredentials, so the instance
          // still considers itself authenticated.
          expect(auth.isAuthenticated, isTrue);
          verifyNever(
            () => httpClient.post(
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          );
        });
      });

      test('revokes the refresh token at the revocation endpoint', () async {
        await runWithOverrides(
          () => auth.login(prompt: (_) {}),
        );

        expect(await runWithOverrides(() => auth.logout()), isTrue);

        final captured = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;

        expect(
          captured[0],
          equals(Uri.parse('https://auth.shorebird.dev/revoke')),
        );
        expect(
          captured[1],
          equals({
            'token': refreshToken,
            'token_type_hint': 'refresh_token',
            'client_id': 'shorebird-cli',
          }),
        );
      });

      test(
        'reports failure and clears credentials when the server refuses',
        () async {
          await runWithOverrides(
            () => auth.login(prompt: (_) {}),
          );
          stubRevocation(
            () async => http.Response(
              '{"error":"internal_error"}',
              HttpStatus.internalServerError,
            ),
          );

          expect(await runWithOverrides(() => auth.logout()), isFalse);
          expect(auth.isAuthenticated, isFalse);
          expect(File(auth.credentialsFilePath).existsSync(), isFalse);
          verify(
            () => logger.detail(
              any(that: contains('Token revocation failed (500)')),
            ),
          ).called(1);
        },
      );

      test(
        'reports failure and clears credentials when the server is unreachable',
        () async {
          await runWithOverrides(
            () => auth.login(prompt: (_) {}),
          );
          expect(auth.isAuthenticated, isTrue);
          stubRevocation(
            () async => throw const SocketException('no internet'),
          );

          expect(await runWithOverrides(() => auth.logout()), isFalse);
          expect(auth.email, isNull);
          expect(auth.isAuthenticated, isFalse);
          expect(File(auth.credentialsFilePath).existsSync(), isFalse);
          verify(
            () => logger.detail(any(that: contains('no internet'))),
          ).called(1);
        },
      );

      test('skips revocation when no refresh token', () async {
        accessCredentials = oauth2.AccessCredentials(
          accessToken,
          null, // no refresh token
          scopes,
        );
        auth = buildAuth();
        writeCredentials();
        auth = buildAuth();

        expect(await runWithOverrides(() => auth.logout()), isTrue);

        verifyNever(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        );
        expect(File(auth.credentialsFilePath).existsSync(), isFalse);
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

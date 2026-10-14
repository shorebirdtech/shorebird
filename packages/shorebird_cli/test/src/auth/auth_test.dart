import 'dart:convert';
import 'dart:io' as io show Platform;
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
import '../helpers.dart';
import '../matchers.dart';
import '../mocks.dart';

const shorebirdJwtIssuer = 'https://auth.shorebird.dev';

void main() {
  useTempWorkingDirectory();
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

    Auth buildAuth({RunProcessSync? runProcessSync}) {
      return runWithOverrides(
        () => Auth(
          credentialsDir: credentialsDir,
          httpClient: httpClient,
          runProcessSync: runProcessSync,
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

          test('warns that the credentials could not be read', () {
            verify(
              () => logger.warn(
                any(that: contains('could not be read')),
              ),
            ).called(1);
          });
        });

        for (final (description, contents) in [
          ('a JSON value that is not an object', '[]'),
          ('a field of the wrong type', '{"accessToken": 42}'),
          (
            'a non-UTC expiry',
            '{"accessToken":{"type":"Bearer","data":"x",'
                '"expiry":"2024-01-01T00:00:00"},"scopes":[]}',
          ),
        ]) {
          group('when credentials are $description', () {
            setUp(() {
              File(
                p.join(credentialsDir, 'credentials.json'),
              ).writeAsStringSync(contents);
              auth = buildAuth();
            });

            test('warns and treats the user as logged out', () {
              expect(auth.isAuthenticated, isFalse);
              verify(
                () => logger.warn(
                  any(that: contains('could not be read')),
                ),
              ).called(1);
            });

            test('logout still removes the file', () async {
              await runWithOverrides(auth.logout);
              expect(
                File(p.join(credentialsDir, 'credentials.json')).existsSync(),
                isFalse,
              );
            });
          });
        }

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
          late List<oauth2.AccessCredentials> onRefreshCredentialsCalls;

          setUp(() {
            onRefreshCredentialsCalls = [];
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
              onRefreshCredentials: onRefreshCredentialsCalls.add,
            );
          });

          void answerRefreshWith(http.Response response) {
            when(
              () => httpClient.post(
                any(),
                headers: any(named: 'headers'),
                body: any(named: 'body'),
              ),
            ).thenAnswer((_) async => response);
          }

          Future<void> expectExit(ExitCode code) async {
            await expectLater(
              () => runWithOverrides(
                () => client.get(Uri.parse('https://example.com')),
              ),
              exitsWithCode(code),
            );
            verifyNever(() => httpClient.send(any()));
            expect(onRefreshCredentialsCalls, isEmpty);
          }

          // Any RFC 6749 section 5.2 error response: the credentials will
          // not refresh again.
          group('with an OAuth error response', () {
            for (final (status, code, description, shown) in [
              (400, 'invalid_grant', null, 'invalid_grant'),
              (
                401,
                'invalid_client',
                'Unknown client',
                'invalid_client: Unknown client',
              ),
              (400, 'unauthorized_client', null, 'unauthorized_client'),
              // A 429 is a 4xx like any other once it carries an OAuth error.
              (429, 'rate_limited', null, 'rate_limited'),
            ]) {
              test(
                'asks the user to log in again on a $status $code',
                () async {
                  answerRefreshWith(
                    http.Response(
                      jsonEncode({
                        'error': code,
                        'error_description': ?description,
                      }),
                      status,
                    ),
                  );

                  await expectExit(ExitCode.software);
                  verify(
                    () => logger.err(
                      'The Shorebird auth service rejected your stored '
                      'credentials ($shown).',
                    ),
                  ).called(1);
                  verify(
                    () => logger.info(
                      'Run ${lightCyan.wrap('shorebird login')} to log in '
                      'again.',
                    ),
                  ).called(1);
                },
              );
            }
          });

          // No usable answer says nothing about the credentials.
          group('without a usable answer', () {
            Future<void> expectTransient(String reason) async {
              await expectExit(ExitCode.tempFail);
              verify(
                () => logger.err(
                  'Could not refresh your Shorebird credentials: $reason',
                ),
              ).called(1);
              verifyNever(
                () => logger.info(any(that: contains('shorebird login'))),
              );
            }

            void verifyCheckNetwork() {
              verify(
                () => logger.info(
                  'Your login is unchanged. Check your network connection '
                  'and try again.',
                ),
              ).called(1);
            }

            test('reports a 5xx', () async {
              answerRefreshWith(
                http.Response(
                  jsonEncode({'error': 'server_error'}),
                  HttpStatus.badGateway,
                ),
              );
              await expectTransient('The Shorebird auth service answered 502.');
              verifyCheckNetwork();
            });

            test('reports a 429 that is not an OAuth error response', () async {
              answerRefreshWith(
                http.Response('Too Many Requests', HttpStatus.tooManyRequests),
              );
              await expectTransient('Too many requests.');
              verify(
                () => logger.info(
                  'Your login is unchanged. Try again shortly.',
                ),
              ).called(1);
            });

            test('reports a 4xx that is not an OAuth error response', () async {
              answerRefreshWith(
                http.Response('<html>nope</html>', HttpStatus.forbidden),
              );
              await expectTransient('The Shorebird auth service answered 403.');
              verifyCheckNetwork();
            });

            test('reports a 200 that is not a token response', () async {
              answerRefreshWith(
                http.Response('<html>ok</html>', HttpStatus.ok),
              );
              await expectTransient(
                'The auth service sent an unexpected token response.',
              );
              verifyCheckNetwork();
            });

            test('reports a network failure', () async {
              when(
                () => httpClient.post(
                  any(),
                  headers: any(named: 'headers'),
                  body: any(named: 'body'),
                ),
              ).thenThrow(const SocketException('no route to host'));
              await expectTransient(
                'Could not reach the Shorebird auth service.',
              );
              verifyCheckNetwork();
              verify(
                () => logger.detail(
                  any(that: contains('no route to host')),
                ),
              ).called(1);
            });
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

      // Any RFC 6749 section 5.2 error response means the stored credentials
      // will not refresh, whichever code it carries.
      group('when the refresh is refused', () {
        setUp(writeCredentials);

        for (final (status, code) in [
          (HttpStatus.badRequest, 'invalid_grant'),
          (HttpStatus.unauthorized, 'invalid_grant'),
          (HttpStatus.unauthorized, 'invalid_client'),
          (HttpStatus.badRequest, 'invalid_request'),
          (HttpStatus.badRequest, 'unauthorized_client'),
          (HttpStatus.tooManyRequests, 'rate_limited'),
        ]) {
          test('returns false for a $status $code', () async {
            answerRefreshWith(
              http.Response(jsonEncode({'error': code}), status),
            );
            auth = buildAuth();
            expect(await runWithOverrides(auth.hasValidCredentials), isFalse);
          });
        }
      });

      // A 4xx that is not an OAuth error response, a plain 429 included,
      // says nothing about the credentials.
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

        test('rethrows a 429 that is not an OAuth error response', () async {
          await expectRethrows(
            http.Response('Too Many Requests', HttpStatus.tooManyRequests),
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

        test('rethrows a 200 that is not a token response', () async {
          answerRefreshWith(http.Response('<html>ok</html>', HttpStatus.ok));
          auth = buildAuth();
          await expectLater(
            runWithOverrides(auth.hasValidCredentials),
            throwsA(isA<ShorebirdAuthException>()),
          );
          expect(File(auth.credentialsFilePath).existsSync(), isTrue);
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

    // Separate Auth instances on one credentials file stand in for separate
    // shorebird processes started from one login, as when `shorebird release
    // android` and `shorebird release ios` run in two terminals.
    group('when several processes share the credentials file', () {
      // A Shorebird-issued access token told apart from the others by its
      // `jti`.
      String accessTokenNamed(String name) {
        String encode(Map<String, Object> json) =>
            base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
        return [
          encode({'alg': 'HS256', 'kid': '1234', 'typ': 'JWT'}),
          encode({
            'iss': shorebirdJwtIssuer,
            'aud': 'shorebird',
            'sub': '12345',
            'email': email,
            'email_verified': true,
            'iat': 1234,
            'exp': 6789,
            'jti': name,
          }),
          'dGVzdA',
        ].join('.');
      }

      oauth2.AccessCredentials credentialsNamed(
        String name, {
        required String refreshToken,
        required bool expired,
      }) {
        return oauth2.AccessCredentials(
          oauth2.AccessToken(
            'Bearer',
            accessTokenNamed(name),
            DateTime.now().add(Duration(minutes: expired ? -1 : 10)).toUtc(),
          ),
          refreshToken,
          scopes,
        );
      }

      void storeCredentials(oauth2.AccessCredentials credentials) {
        File(
          p.join(credentialsDir, 'credentials.json'),
        ).writeAsStringSync(jsonEncode(credentials.toJson()));
      }

      oauth2.AccessCredentials readStoredCredentials() {
        return oauth2.AccessCredentials.fromJson(
          jsonDecode(
                File(
                  p.join(credentialsDir, 'credentials.json'),
                ).readAsStringSync(),
              )
              as Map<String, dynamic>,
        );
      }

      http.Response tokenResponse(String name, String refreshToken) {
        return http.Response(
          jsonEncode({
            'access_token': accessTokenNamed(name),
            'refresh_token': refreshToken,
            'token_type': 'Bearer',
            'expires_in': 900,
          }),
          HttpStatus.ok,
        );
      }

      // The refresh tokens presented to the auth service, in order.
      late List<String?> presentedRefreshTokens;
      // The access tokens sent to the API, in order.
      late List<String?> sentAccessTokens;
      // Answers each refresh; by default rotates to `rotated`.
      late Future<http.Response> Function(String? refreshToken) onRefresh;

      setUp(() {
        presentedRefreshTokens = [];
        sentAccessTokens = [];
        onRefresh = (_) async => tokenResponse('rotated', 'sb_rt_rotated');
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((invocation) {
          final body = invocation.namedArguments[#body] as Map<String, String>;
          presentedRefreshTokens.add(body['refresh_token']);
          return onRefresh(body['refresh_token']);
        });
        when(() => httpClient.send(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as http.BaseRequest;
          sentAccessTokens.add(
            request.headers['Authorization']?.replaceFirst('Bearer ', ''),
          );
          return http.StreamedResponse(const Stream.empty(), HttpStatus.ok);
        });
        storeCredentials(
          credentialsNamed(
            'expired',
            refreshToken: refreshToken,
            expired: true,
          ),
        );
      });

      Future<void> sendRequest(Auth auth) => runWithOverrides(
        () => auth.client.get(Uri.parse('https://example.com')),
      );

      test('a second process uses the credentials the first refreshed, '
          'without refreshing', () async {
        final first = buildAuth();
        final second = buildAuth();

        await sendRequest(first);
        await sendRequest(second);

        expect(presentedRefreshTokens, equals([refreshToken]));
        expect(
          sentAccessTokens,
          equals([accessTokenNamed('rotated'), accessTokenNamed('rotated')]),
        );
        expect(readStoredCredentials().refreshToken, equals('sb_rt_rotated'));
      });

      test(
        'a later client from the same Auth does not refresh again',
        () async {
          final auth = buildAuth();

          await sendRequest(auth);
          await sendRequest(auth);

          expect(presentedRefreshTokens, equals([refreshToken]));
        },
      );

      test('refreshes and stores the result when the stored access token has '
          'expired', () async {
        final auth = buildAuth();

        await sendRequest(auth);

        expect(presentedRefreshTokens, equals([refreshToken]));
        expect(sentAccessTokens, equals([accessTokenNamed('rotated')]));
        final stored = readStoredCredentials();
        expect(stored.refreshToken, equals('sb_rt_rotated'));
        expect(stored.accessToken.data, equals(accessTokenNamed('rotated')));
      });

      test('refreshes with the newest refresh token on disk when its access '
          'token has expired too', () async {
        final auth = buildAuth();
        storeCredentials(
          credentialsNamed('newer', refreshToken: 'sb_rt_newer', expired: true),
        );

        await sendRequest(auth);

        expect(presentedRefreshTokens, equals(['sb_rt_newer']));
        expect(sentAccessTokens, equals([accessTokenNamed('rotated')]));
      });

      test(
        'writes the credentials file by renaming a complete file over it',
        () async {
          final restricted = <String>[];
          final auth = buildAuth(
            runProcessSync: (executable, arguments) {
              restricted.add(arguments.last);
              return Process.runSync(executable, arguments);
            },
          );

          await sendRequest(auth);

          final credentialsPath = p.join(credentialsDir, 'credentials.json');
          if (!io.Platform.isWindows) {
            // Restricted and written under another name, then renamed.
            expect(restricted, hasLength(1));
            expect(restricted.single, isNot(equals(credentialsPath)));
            expect(p.dirname(restricted.single), equals(credentialsDir));
            expect(
              File(credentialsPath).statSync().mode & 0x1ff,
              equals(0x180),
            );
          }
          expect(
            Directory(credentialsDir).listSync().map((e) => p.basename(e.path)),
            equals(['credentials.json']),
          );
          expect(readStoredCredentials().refreshToken, equals('sb_rt_rotated'));
        },
      );

      test('refreshes with the credentials in memory when the file is '
          'gone', () async {
        final auth = buildAuth();
        File(p.join(credentialsDir, 'credentials.json')).deleteSync();

        await sendRequest(auth);

        expect(presentedRefreshTokens, equals([refreshToken]));
        expect(sentAccessTokens, equals([accessTokenNamed('rotated')]));
        expect(readStoredCredentials().refreshToken, equals('sb_rt_rotated'));
      });

      test('carries on with the refreshed credentials and warns when they '
          'cannot be saved', () async {
        final auth = buildAuth();
        final credentialsPath = p.join(credentialsDir, 'credentials.json');
        File(credentialsPath).deleteSync();
        // A directory in its place makes both the rename and an in-place
        // write fail.
        Directory(credentialsPath).createSync();

        await sendRequest(auth);

        expect(sentAccessTokens, equals([accessTokenNamed('rotated')]));
        verify(
          () => logger.warn(
            any(
              that: contains(
                'Could not save your refreshed Shorebird credentials',
              ),
            ),
          ),
        ).called(1);
        // The temporary file holds a refresh token, so it is removed.
        expect(
          Directory(credentialsDir).listSync().map((e) => p.basename(e.path)),
          equals(['credentials.json']),
        );
      });

      test(
        'saves the refreshed credentials while another process has the '
        'file open',
        () async {
          final auth = buildAuth();
          final open = File(
            p.join(credentialsDir, 'credentials.json'),
          ).openSync();
          try {
            await sendRequest(auth);
          } finally {
            open.closeSync();
          }

          expect(readStoredCredentials().refreshToken, equals('sb_rt_rotated'));
          expect(
            Directory(credentialsDir).listSync().map((e) => p.basename(e.path)),
            equals(['credentials.json']),
          );
          // Windows refuses the rename while the file is open, so the
          // credentials are written in place. Elsewhere the rename succeeds.
          void wroteInPlace() =>
              logger.detail(any(that: contains('writing it in place')));
          if (io.Platform.isWindows) {
            verify(wroteInPlace).called(1);
          } else {
            verifyNever(wroteInPlace);
          }
        },
      );

      test('hasValidCredentials refreshes with the newest refresh token on '
          'disk, even when its access token is current', () async {
        final auth = buildAuth();
        storeCredentials(
          credentialsNamed(
            'newer',
            refreshToken: 'sb_rt_newer',
            expired: false,
          ),
        );

        expect(await runWithOverrides(auth.hasValidCredentials), isTrue);

        expect(presentedRefreshTokens, equals(['sb_rt_newer']));
        expect(readStoredCredentials().refreshToken, equals('sb_rt_rotated'));
      });
    });

    group('login', () {
      test(
        'writes the credentials file readable by the owner only',
        () async {
          final credentialsFile = File(
            p.join(credentialsDir, 'credentials.json'),
          )..writeAsStringSync('');
          // Start from a world-readable file, as older CLIs wrote it.
          Process.runSync('chmod', ['644', credentialsFile.path]);

          await runWithOverrides(() => auth.login(prompt: (_) {}));

          expect(credentialsFile.statSync().mode & 0x1ff, equals(0x180));
        },
        skip: io.Platform.isWindows
            ? 'Windows has no POSIX file modes.'
            : false,
      );

      test(
        'logs at detail level and still writes when chmod fails',
        () async {
          auth = buildAuth(
            runProcessSync: (executable, arguments) =>
                ProcessResult(0, 1, '', 'Operation not permitted'),
          );

          await runWithOverrides(() => auth.login(prompt: (_) {}));

          final credentialsPath = p.join(credentialsDir, 'credentials.json');
          verify(
            () => logger.detail(
              'Failed to restrict permissions on $credentialsPath '
              '(chmod exited 1): Operation not permitted',
            ),
          ).called(1);
          expect(File(credentialsPath).existsSync(), isTrue);
          expect(buildAuth().isAuthenticated, isTrue);
        },
        skip: io.Platform.isWindows ? 'Windows does not run chmod.' : false,
      );

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

import 'dart:convert';
import 'dart:io' as io show Platform;
import 'dart:io' hide Platform;

import 'package:cli_util/cli_util.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:path/path.dart' as p;
import 'package:platform/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/credential_source.dart';
import 'package:shorebird_cli/src/auth/github_actions_oidc.dart';
import 'package:shorebird_cli/src/auth/oidc_credential_source.dart';
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
final tokenEndpoint = Uri.parse('https://auth.shorebird.dev/token');
final _defaultTokenEndpoint = tokenEndpoint;
final devAuthServiceUri = Uri.parse('https://auth-dev.shorebird.dev');
final devTokenEndpoint = Uri.parse('https://auth-dev.shorebird.dev/token');

void main() {
  useTempWorkingDirectory();
  group('scoped', () {
    test('creates instance with default constructor', () {
      // Constructing Auth reads, and may move, the stored login, so point
      // the config directory at a temporary one, never the real one.
      final home = Directory.systemTemp.createTempSync().path;
      final environment = {
        'HOME': home,
        'APPDATA': home,
        'XDG_CONFIG_HOME': p.join(home, '.config'),
      };
      final instance = runScoped(
        () => auth,
        values: {
          authRef,
          httpClientRef.overrideWith(MockHttpClient.new),
          platformRef.overrideWith(
            () => TestNativePlatform(environment: environment),
          ),
          shorebirdEnvRef.overrideWith(ShorebirdEnv.new),
        },
      );
      final configHome = BaseDirectories(
        executableName,
        environment: environment,
      ).configHome;
      expect(p.isWithin(home, configHome), isTrue);
      expect(
        instance.credentialsFilePath,
        p.join(configHome, 'credentials-v2.json'),
      );
      expect(
        instance.legacyCredentialsFilePath,
        p.join(configHome, 'credentials.json'),
      );
    });
  });

  group(Auth, () {
    const refreshToken = 'sb_rt_test';
    // Opaque to the CLI, as access tokens are to any OAuth client.
    const shorebirdAccessToken = 'sb_at_test';
    const email = 'test@email.com';
    const user = PrivateUser(
      id: 42,
      email: email,
      jwtIssuer: shorebirdJwtIssuer,
    );

    /// Credentials as the auth service issues them, expiring in ten minutes
    /// or, when [expired], a minute ago.
    oauth2.Credentials credentialsWith({
      String accessToken = shorebirdAccessToken,
      String? refreshToken = refreshToken,
      bool expired = false,
      Uri? tokenEndpoint,
    }) {
      return oauth2.Credentials(
        accessToken,
        refreshToken: refreshToken,
        tokenEndpoint: tokenEndpoint ?? _defaultTokenEndpoint,
        scopes: ['api'],
        expiration: DateTime.now().add(Duration(minutes: expired ? -1 : 10)),
      );
    }

    late oauth2.Credentials accessCredentials;
    final deviceAuthorization = DeviceAuthorization(
      deviceCode: 'device-code',
      userCode: 'BEST-CAKE',
      verificationUri: Uri.parse('https://auth.shorebird.dev/device'),
      expiresIn: const Duration(minutes: 15),
      interval: const Duration(seconds: 5),
    );
    late String credentialsDir;
    late String credentialsPath;
    late String legacyCredentialsPath;
    late http.Client httpClient;
    http.Client? loginHttpClient;
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
          // The same mock, so tests stub one client for every request.
          nonRetryingHttpClientRef.overrideWith(() => httpClient),
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
                Future<void> Function(oauth2.Credentials)? completeLogin,
              }) async {
                loginHttpClient = httpClient;
                await completeLogin?.call(accessCredentials);
                return accessCredentials;
              },
          obtainCredentialsViaDeviceLogin:
              ({
                required http.Client httpClient,
                required Uri authBaseUrl,
                required void Function(DeviceAuthorization) userPrompt,
              }) async {
                loginHttpClient = httpClient;
                userPrompt(deviceAuthorization);
                return accessCredentials;
              },
        ),
      );
    }

    /// Writes [credentials] to the credentials file, or the file at [path],
    /// with [email] as a login stores it.
    void storeCredentials(
      oauth2.Credentials credentials, {
      String? email,
      String? path,
    }) {
      File(path ?? credentialsPath).writeAsStringSync(
        jsonEncode({
          ...jsonDecode(credentials.toJson()) as Map<String, Object?>,
          'email': ?email,
        }),
      );
    }

    void writeCredentials() =>
        storeCredentials(accessCredentials, email: email);

    /// The `email` field of the credentials file.
    Object? readStoredEmail() {
      final json = jsonDecode(File(credentialsPath).readAsStringSync());
      return (json as Map)['email'];
    }

    oauth2.Credentials readStoredCredentials() {
      return oauth2.Credentials.fromJson(
        File(credentialsPath).readAsStringSync(),
      );
    }

    /// A successful token response, as the auth service sends it.
    http.Response tokenResponse({
      String accessToken = shorebirdAccessToken,
      String refreshToken = 'sb_rt_rotated',
    }) {
      return http.Response(
        jsonEncode({
          'access_token': accessToken,
          'refresh_token': refreshToken,
          'token_type': 'Bearer',
          'expires_in': 900,
        }),
        HttpStatus.ok,
        headers: {'content-type': 'application/json'},
      );
    }

    /// An RFC 6749 section 5.2 error response.
    http.Response oauthErrorResponse(
      String error, {
      int status = HttpStatus.badRequest,
      String? description,
    }) {
      return http.Response(
        jsonEncode({'error': error, 'error_description': ?description}),
        status,
        headers: {'content-type': 'application/json'},
      );
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

    void answerApiRequests() {
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
      );
    }

    setUp(() {
      loginHttpClient = null;
      accessCredentials = credentialsWith();
      credentialsDir = Directory.systemTemp.createTempSync().path;
      credentialsPath = p.join(credentialsDir, 'credentials-v2.json');
      legacyCredentialsPath = p.join(credentialsDir, 'credentials.json');
      httpClient = MockHttpClient();
      codePushClient = MockCodePushClient();
      logger = MockShorebirdLogger();
      platform = TestNativePlatform(environment: {});
      shorebirdEnv = MockShorebirdEnv();

      when(() => codePushClient.getCurrentUser()).thenAnswer((_) async => user);
      when(
        () => shorebirdEnv.authServiceUri,
      ).thenReturn(Uri.parse('https://auth.shorebird.dev'));
      when(() => shorebirdEnv.hostedUri).thenReturn(null);

      auth = buildAuth();
    });

    group('isAuthenticated', () {
      test('is true for stored credentials', () {
        writeCredentials();
        auth = buildAuth();
        expect(auth.isAuthenticated, isTrue);
        expect(auth.isUsingApiKey, isFalse);
        expect(auth.email, equals(email));
      });

      for (final (description, contents) in [
        ('not JSON', 'invalid credentials'),
        ('a JSON value that is not an object', '[]'),
        ('a field of the wrong type', '{"accessToken": 42}'),
        ('missing scopes', '{"accessToken": "x"}'),
        (
          'an expiration that is not a timestamp',
          '{"accessToken": "x", "expiration": "soon", "scopes": []}',
        ),
      ]) {
        group('when credentials are $description', () {
          setUp(() {
            File(credentialsPath).writeAsStringSync(contents);
            auth = buildAuth();
          });

          test('warns and treats the user as logged out', () {
            expect(auth.isAuthenticated, isFalse);
            expect(auth.client, same(httpClient));
            verify(
              () => logger.warn(any(that: contains('could not be read'))),
            ).called(1);
          });

          test('logout still removes the file', () async {
            await runWithOverrides(auth.logout);
            expect(File(credentialsPath).existsSync(), isFalse);
          });
        });
      }

      test('is true for stored credentials without an email', () {
        storeCredentials(accessCredentials);
        auth = buildAuth();
        expect(auth.isAuthenticated, isTrue);
        expect(auth.email, isNull);
      });

      test('ignores an email field that is not a string', () {
        File(credentialsPath).writeAsStringSync(
          jsonEncode({
            ...jsonDecode(accessCredentials.toJson()) as Map<String, Object?>,
            'email': 42,
          }),
        );
        auth = buildAuth();
        expect(auth.isAuthenticated, isTrue);
        expect(auth.email, isNull);
      });
    });

    group('when only a legacy credentials file exists', () {
      /// Credentials in `package:googleapis_auth`'s `AccessCredentials`
      /// format, as CLIs before `package:oauth2` wrote them.
      Map<String, Object?> legacyCredentials({
        String accessToken = shorebirdAccessToken,
        String? refreshToken = refreshToken,
        Duration expiresIn = const Duration(minutes: 10),
        String? idToken,
      }) {
        return {
          'accessToken': {
            'type': 'Bearer',
            'data': accessToken,
            'expiry': DateTime.now().add(expiresIn).toUtc().toIso8601String(),
          },
          'refreshToken': ?refreshToken,
          'idToken': idToken,
          'scopes': <String>[],
        };
      }

      void writeLegacyCredentials(Map<String, Object?> json) {
        File(legacyCredentialsPath).writeAsStringSync(jsonEncode(json));
      }

      test('moves the login to the credentials file', () {
        writeLegacyCredentials(legacyCredentials());

        auth = buildAuth();

        expect(auth.isAuthenticated, isTrue);
        // The legacy file stores no email; fetchEmail asks the API for it.
        expect(auth.email, isNull);
        expect(File(legacyCredentialsPath).existsSync(), isFalse);
        final stored = readStoredCredentials();
        expect(stored.accessToken, equals(shorebirdAccessToken));
        expect(stored.refreshToken, equals(refreshToken));
        expect(stored.tokenEndpoint, equals(tokenEndpoint));
        expect(stored.scopes, equals(['api']));
        expect(stored.isExpired, isFalse);
      });

      test('moves credentials that also carry the token as idToken', () {
        // How CLI versions before the access token was sent as itself wrote
        // credentials.json.
        writeLegacyCredentials(
          legacyCredentials(idToken: shorebirdAccessToken),
        );

        auth = buildAuth();

        expect(auth.isAuthenticated, isTrue);
        expect(readStoredCredentials().accessToken, shorebirdAccessToken);
      });

      test('refreshes moved credentials at the token endpoint', () async {
        writeLegacyCredentials(
          legacyCredentials(expiresIn: const Duration(minutes: -1)),
        );
        answerRefreshWith(tokenResponse());
        answerApiRequests();

        auth = buildAuth();
        await runWithOverrides(
          () => auth.client.get(Uri.parse('https://example.com')),
        );

        final captured = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;
        expect(captured[0], equals(tokenEndpoint));
        expect(
          captured[1],
          equals({
            'grant_type': 'refresh_token',
            'refresh_token': refreshToken,
            'scope': 'api',
            'client_id': 'shorebird-cli',
          }),
        );
        expect(readStoredCredentials().refreshToken, equals('sb_rt_rotated'));
      });

      test('ignores the legacy file once the credentials file exists', () {
        storeCredentials(credentialsWith(refreshToken: 'sb_rt_current'));
        writeLegacyCredentials(legacyCredentials(refreshToken: 'sb_rt_old'));

        auth = buildAuth();

        expect(readStoredCredentials().refreshToken, equals('sb_rt_current'));
        expect(File(legacyCredentialsPath).existsSync(), isTrue);
      });

      test('uses the legacy file in place when it cannot be moved', () {
        writeLegacyCredentials(legacyCredentials());
        // A directory in its place makes the write fail.
        Directory(credentialsPath).createSync();

        auth = buildAuth();

        expect(auth.isAuthenticated, isTrue);
        expect(File(legacyCredentialsPath).existsSync(), isTrue);
        verify(
          () => logger.detail(any(that: contains('Could not move'))),
        ).called(1);
      });

      test('warns when the legacy file cannot be read', () {
        File(legacyCredentialsPath).writeAsStringSync('{"accessToken": 42}');

        auth = buildAuth();

        expect(auth.isAuthenticated, isFalse);
        verify(
          () => logger.warn(any(that: contains('could not be read'))),
        ).called(1);
      });
    });

    group(
      'when credentials-v2.json holds a login for another auth service',
      () {
        late String devCredentialsPath;

        setUp(() {
          devCredentialsPath = p.join(
            credentialsDir,
            'credentials-v2-auth-dev.shorebird.dev.json',
          );
          storeCredentials(
            credentialsWith(tokenEndpoint: devTokenEndpoint),
            email: email,
          );
        });

        test("moves it to that service's file and is logged out", () {
          auth = buildAuth();

          expect(auth.isAuthenticated, isFalse);
          expect(File(credentialsPath).existsSync(), isFalse);
          final moved = oauth2.Credentials.fromJson(
            File(devCredentialsPath).readAsStringSync(),
          );
          expect(moved.tokenEndpoint, equals(devTokenEndpoint));
          verifyNever(() => logger.warn(any()));
        });

        test('warns and ignores it when that service has a file', () {
          storeCredentials(
            credentialsWith(
              accessToken: 'sb_at_dev',
              tokenEndpoint: devTokenEndpoint,
            ),
            path: devCredentialsPath,
          );

          auth = buildAuth();

          expect(auth.isAuthenticated, isFalse);
          expect(File(credentialsPath).existsSync(), isTrue);
          verify(
            () => logger.warn(
              any(
                that: contains(
                  'are for auth-dev.shorebird.dev, not auth.shorebird.dev',
                ),
              ),
            ),
          ).called(1);
        });

        test('logs when it cannot be moved', () {
          // A directory in its place makes the rename fail.
          Directory(devCredentialsPath).createSync();

          auth = buildAuth();

          expect(auth.isAuthenticated, isFalse);
          expect(File(credentialsPath).existsSync(), isTrue);
          verify(
            () => logger.detail(any(that: contains('Could not move'))),
          ).called(1);
        });
      },
    );

    test('uses stored credentials that name no token endpoint', () {
      storeCredentials(oauth2.Credentials(shorebirdAccessToken));
      auth = buildAuth();
      expect(auth.isAuthenticated, isTrue);
    });

    group('when the auth service is not the default one', () {
      late String devCredentialsPath;

      setUp(() {
        devCredentialsPath = p.join(
          credentialsDir,
          'credentials-v2-auth-dev.shorebird.dev.json',
        );
        accessCredentials = credentialsWith(tokenEndpoint: devTokenEndpoint);
        when(() => shorebirdEnv.authServiceUri).thenReturn(devAuthServiceUri);
        auth = buildAuth();
      });

      test('stores its login in a file named for its host', () async {
        expect(auth.credentialsFilePath, equals(devCredentialsPath));

        await runWithOverrides(() => auth.login(prompt: (_) {}));

        expect(File(devCredentialsPath).existsSync(), isTrue);
        expect(File(credentialsPath).existsSync(), isFalse);
        expect(buildAuth().isAuthenticated, isTrue);
      });

      test('names the port in the file name when there is one', () {
        when(
          () => shorebirdEnv.authServiceUri,
        ).thenReturn(Uri.parse('http://localhost:8080'));
        expect(
          buildAuth().credentialsFilePath,
          equals(p.join(credentialsDir, 'credentials-v2-localhost_8080.json')),
        );
      });

      test("ignores the default auth service's login", () async {
        storeCredentials(credentialsWith(), email: email);

        auth = buildAuth();

        expect(auth.isAuthenticated, isFalse);
        expect(auth.client, same(httpClient));
        expect(File(credentialsPath).existsSync(), isTrue);
        verifyNever(() => logger.warn(any()));
      });

      test('logs in while the default auth service is logged in', () async {
        storeCredentials(credentialsWith(accessToken: 'sb_at_prod'));
        auth = buildAuth();

        await runWithOverrides(() => auth.login(prompt: (_) {}));

        expect(auth.isAuthenticated, isTrue);
        expect(
          readStoredCredentials().accessToken,
          equals('sb_at_prod'),
          reason: "The default auth service's login is unchanged.",
        );
      });

      test('moves its login out of credentials-v2.json and uses it', () {
        storeCredentials(
          credentialsWith(tokenEndpoint: devTokenEndpoint),
          email: email,
        );

        auth = buildAuth();

        expect(auth.isAuthenticated, isTrue);
        expect(auth.email, equals(email));
        expect(File(credentialsPath).existsSync(), isFalse);
        expect(File(devCredentialsPath).existsSync(), isTrue);
      });

      test('warns and ignores a login another auth service issued', () {
        storeCredentials(credentialsWith(), path: devCredentialsPath);

        auth = buildAuth();

        expect(auth.isAuthenticated, isFalse);
        verify(
          () => logger.warn(
            any(
              that: allOf(
                contains(devCredentialsPath),
                contains(
                  'are for auth.shorebird.dev, not auth-dev.shorebird.dev',
                ),
                contains('shorebird login'),
              ),
            ),
          ),
        ).called(1);
      });

      test('does not carry a legacy login over', () {
        File(legacyCredentialsPath).writeAsStringSync('{}');

        auth = buildAuth();

        expect(auth.isAuthenticated, isFalse);
        expect(File(legacyCredentialsPath).existsSync(), isTrue);
      });

      test('logout removes only its own login', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('', HttpStatus.ok));
        storeCredentials(credentialsWith());
        File(legacyCredentialsPath).writeAsStringSync('{}');
        storeCredentials(accessCredentials, path: devCredentialsPath);
        auth = buildAuth();

        await runWithOverrides(auth.logout);

        expect(File(devCredentialsPath).existsSync(), isFalse);
        expect(File(credentialsPath).existsSync(), isTrue);
        expect(File(legacyCredentialsPath).existsSync(), isTrue);
        final revoked = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).captured;
        expect((revoked.single as Uri).host, equals('auth-dev.shorebird.dev'));
      });
    });

    group('client', () {
      test('sends the stored access token while it is current', () async {
        answerApiRequests();
        writeCredentials();
        auth = buildAuth();

        final client = auth.client;
        expect(client, isA<AuthenticatedClient>());
        await runWithOverrides(
          () => client.get(Uri.parse('https://example.com')),
        );

        final captured = verify(() => httpClient.send(captureAny())).captured;
        expect(captured, hasLength(1));
        final request = captured.first as http.BaseRequest;
        expect(
          request.headers['authorization'],
          equals('Bearer $shorebirdAccessToken'),
        );
        verifyNever(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        );
      });

      group('when the API refuses the stored access token', () {
        const invalidTokenChallenge =
            'Bearer error="invalid_token", '
            'error_description="The access token is invalid or expired.", '
            'error_uri="https://example.com/errors"';

        void answerApiRequestsWith({
          required int status,
          Map<String, String> headers = const {},
        }) {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              status,
              headers: headers,
            ),
          );
        }

        Future<http.Response> sendRequest() => runWithOverrides(
          () => auth.client.get(Uri.parse('https://example.com')),
        );

        setUp(() {
          writeCredentials();
          auth = buildAuth();
        });

        test('throws the bearer challenge as oauth2 does', () async {
          answerApiRequestsWith(
            status: HttpStatus.unauthorized,
            headers: {'www-authenticate': invalidTokenChallenge},
          );

          await expectLater(
            sendRequest(),
            throwsA(
              isA<oauth2.AuthorizationException>()
                  .having((e) => e.error, 'error', 'invalid_token')
                  .having(
                    (e) => e.description,
                    'description',
                    'The access token is invalid or expired.',
                  )
                  .having(
                    (e) => e.uri,
                    'uri',
                    Uri.parse('https://example.com/errors'),
                  ),
            ),
          );
        });

        test('throws a challenge without a description or uri', () async {
          answerApiRequestsWith(
            status: HttpStatus.unauthorized,
            headers: {'www-authenticate': 'Bearer error="invalid_token"'},
          );

          await expectLater(
            sendRequest(),
            throwsA(
              isA<oauth2.AuthorizationException>()
                  .having((e) => e.description, 'description', isNull)
                  .having((e) => e.uri, 'uri', isNull),
            ),
          );
        });

        for (final (description, status, headers) in [
          (
            'a 401 without a challenge',
            HttpStatus.unauthorized,
            <String, String>{},
          ),
          (
            'a bare bearer challenge',
            HttpStatus.unauthorized,
            {'www-authenticate': 'Bearer'},
          ),
          (
            'a challenge for another scheme',
            HttpStatus.unauthorized,
            {'www-authenticate': 'Basic realm="shorebird"'},
          ),
          (
            'a challenge that cannot be parsed',
            HttpStatus.unauthorized,
            {'www-authenticate': '"not a challenge'},
          ),
          (
            'a 403 with a challenge',
            HttpStatus.forbidden,
            {'www-authenticate': 'Bearer error="insufficient_scope"'},
          ),
        ]) {
          test('returns $description as a response', () async {
            answerApiRequestsWith(
              status: status,
              headers: headers,
            );

            final response = await sendRequest();
            expect(response.statusCode, equals(status));
          });
        }
      });

      test('returns a 401 challenge to an API key as a response', () async {
        platform = platform.copyWith(
          environment: {shorebirdTokenEnvVar: 'sb_api_abc123'},
        );
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.unauthorized,
            headers: {'www-authenticate': 'Bearer error="invalid_token"'},
          ),
        );
        auth = buildAuth();

        final response = await runWithOverrides(
          () => auth.client.get(Uri.parse('https://example.com')),
        );
        expect(response.statusCode, equals(HttpStatus.unauthorized));
      });

      test('returns a plain http client when credentials are not present', () {
        expect(auth.client, same(httpClient));
      });

      group('when the stored access token has expired', () {
        setUp(() {
          storeCredentials(credentialsWith(expired: true));
          auth = buildAuth();
        });

        Future<void> sendRequest() => runWithOverrides(
          () => auth.client.get(Uri.parse('https://example.com')),
        );

        test('refreshes as shorebird-cli and sends the new token', () async {
          const rotatedAccessToken = '$shorebirdAccessToken.rotated';
          answerRefreshWith(tokenResponse(accessToken: rotatedAccessToken));
          answerApiRequests();

          await sendRequest();

          final refresh = verify(
            () => httpClient.post(
              captureAny(),
              headers: any(named: 'headers'),
              body: captureAny(named: 'body'),
            ),
          ).captured;
          expect(refresh[0], equals(tokenEndpoint));
          expect(
            refresh[1],
            equals({
              'grant_type': 'refresh_token',
              'refresh_token': refreshToken,
              'scope': 'api',
              'client_id': 'shorebird-cli',
            }),
          );
          final request =
              verify(() => httpClient.send(captureAny())).captured.single
                  as http.BaseRequest;
          expect(
            request.headers['authorization'],
            equals('Bearer $rotatedAccessToken'),
          );
          expect(
            readStoredCredentials().refreshToken,
            equals('sb_rt_rotated'),
          );
        });

        Future<void> expectExit(ExitCode code) async {
          await expectLater(sendRequest, exitsWithCode(code));
          verifyNever(() => httpClient.send(any()));
          expect(readStoredCredentials().refreshToken, equals(refreshToken));
        }

        // Any RFC 6749 section 5.2 error response: the credentials will not
        // refresh again.
        for (final (status, code, description, shown) in [
          (400, 'invalid_grant', null, 'invalid_grant'),
          (
            401,
            'invalid_client',
            'Unknown client',
            'invalid_client: Unknown client',
          ),
          (400, 'unauthorized_client', null, 'unauthorized_client'),
        ]) {
          test('asks the user to log in again on a $status $code', () async {
            answerRefreshWith(
              oauthErrorResponse(
                code,
                status: status,
                description: description,
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
                'Run ${lightCyan.wrap('shorebird login')} to log in again.',
              ),
            ).called(1);
          });
        }

        test('asks the user to log in again with no refresh token', () async {
          storeCredentials(credentialsWith(refreshToken: null, expired: true));
          auth = buildAuth();

          await expectLater(sendRequest, exitsWithCode(ExitCode.software));
          verify(
            () => logger.err('Your Shorebird login has expired.'),
          ).called(1);
          verify(
            () => logger.info(
              'Run ${lightCyan.wrap('shorebird login')} to log in again.',
            ),
          ).called(1);
        });

        // No OAuth answer says nothing about the credentials.
        group('without an OAuth answer', () {
          Future<void> expectTransient(String reason) async {
            await expectExit(ExitCode.tempFail);
            verify(
              () => logger.err(
                'Could not refresh your Shorebird credentials: $reason',
              ),
            ).called(1);
            verify(
              () => logger.info(
                'Your login is unchanged. Check your network connection '
                'and try again.',
              ),
            ).called(1);
            verifyNever(
              () => logger.info(any(that: contains('shorebird login'))),
            );
          }

          for (final (description, response) in [
            (
              'a 5xx',
              http.Response('bad gateway', HttpStatus.badGateway),
            ),
            (
              'a 5xx with an OAuth error body',
              oauthErrorResponse('server_error', status: HttpStatus.badGateway),
            ),
            (
              'a 429',
              http.Response('', HttpStatus.tooManyRequests),
            ),
            (
              'a 4xx that is not an OAuth error response',
              http.Response('<html>nope</html>', HttpStatus.forbidden),
            ),
            (
              'a 200 that is not a token response',
              http.Response(
                '<html>ok</html>',
                HttpStatus.ok,
                headers: {'content-type': 'text/html'},
              ),
            ),
          ]) {
            test('reports $description', () async {
              answerRefreshWith(response);
              await expectTransient(
                'The Shorebird auth service sent an unexpected answer.',
              );
            });
          }

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
            verify(
              () => logger.detail(any(that: contains('no route to host'))),
            ).called(1);
          });
        });
      });

      group('when SHOREBIRD_TOKEN is an API key', () {
        setUp(() {
          platform = platform.copyWith(
            environment: {shorebirdTokenEnvVar: 'sb_api_abc123'},
          );
        });

        test('parses as API key and sets isAuthenticated', () {
          auth = buildAuth();
          expect(auth.isAuthenticated, isTrue);
          expect(auth.isUsingApiKey, isTrue);
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

        test('does not suggest GitHub Actions OIDC', () {
          auth = buildAuth();
          verifyNever(() => logger.info(any()));
        });

        test('trims whitespace from API key', () {
          platform = platform.copyWith(
            environment: {shorebirdTokenEnvVar: '  sb_api_abc123  \n'},
          );
          auth = buildAuth();
          expect(auth.isAuthenticated, isTrue);
        });

        test('sends the API key as the bearer token', () async {
          answerApiRequests();
          auth = buildAuth();
          final client = auth.client;
          expect(client, isA<AuthenticatedClient>());

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

        test('takes priority over credentials file', () async {
          answerApiRequests();
          writeCredentials();
          auth = buildAuth();
          expect(auth.isAuthenticated, isTrue);
          expect(auth.email, isNull);

          await runWithOverrides(
            () => auth.client.get(Uri.parse('https://example.com')),
          );

          final captured = verify(() => httpClient.send(captureAny())).captured;
          final request = captured.single as http.BaseRequest;
          expect(
            request.headers['Authorization'],
            equals('Bearer sb_api_abc123'),
          );
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
    });

    group('credentialKind, accessToken and accessTokenExpiresAt', () {
      test('are null without credentials', () {
        expect(auth.credentialKind, isNull);
        expect(auth.accessTokenExpiresAt, isNull);
      });

      group('with a stored login', () {
        setUp(() {
          writeCredentials();
          auth = buildAuth();
        });

        test('name the login before any request', () {
          expect(auth.credentialKind, equals(CredentialKind.login));
          expect(auth.accessTokenExpiresAt, isNull);
        });

        test('return the access token and its expiry', () async {
          final token = await runWithOverrides(auth.accessToken);
          expect(token, equals(shorebirdAccessToken));
          expect(auth.credentialKind, equals(CredentialKind.login));
          // The credentials file stores the expiry to the millisecond.
          expect(
            auth.accessTokenExpiresAt?.millisecondsSinceEpoch,
            equals(accessCredentials.expiration!.millisecondsSinceEpoch),
          );
        });
      });

      group('with an API key', () {
        setUp(() {
          platform = platform.copyWith(
            environment: {shorebirdTokenEnvVar: 'sb_api_test'},
          );
          auth = buildAuth();
        });

        test('return the key, with no expiry', () async {
          expect(auth.credentialKind, equals(CredentialKind.apiKey));
          final token = await runWithOverrides(auth.accessToken);
          expect(token, equals('sb_api_test'));
          expect(auth.credentialKind, equals(CredentialKind.apiKey));
          expect(auth.accessTokenExpiresAt, isNull);
        });
      });
    });

    group('when GitHub Actions grants an OIDC token request', () {
      const oidcEnvironment = {
        githubActionsEnvVar: 'true',
        actionsIdTokenRequestUrlEnvVar:
            'https://pipelines.actions.githubusercontent.com/idtoken?api-version=2.0',
        actionsIdTokenRequestTokenEnvVar: 'gha-request-token',
        shorebirdProjectIdEnvVar: '42',
      };

      /// Answers the request for a GitHub Actions ID token with a 403, so
      /// that signing in with OIDC fails before an exchange is sent.
      void refuseIdTokenRequests() {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) async => http.Response('Forbidden', 403));
      }

      void answerIdTokenRequests() {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(jsonEncode({'value': 'gha.id'}), 200),
        );
      }

      setUp(() {
        platform = platform.copyWith(environment: oidcEnvironment);
      });

      test('signs in with GitHub Actions OIDC', () {
        auth = buildAuth();
        expect(auth.isAuthenticated, isTrue);
        expect(auth.isUsingGitHubActionsOidc, isTrue);
        expect(auth.unavailableCredentialsReason, isNull);
        verify(
          () => logger.detail(
            '[env] ACTIONS_ID_TOKEN_REQUEST_URL detected, signing in with '
            'GitHub Actions OIDC',
          ),
        ).called(1);
        expect(auth.isUsingApiKey, isFalse);
        expect(auth.email, isNull);
        expect(auth.client, isA<AuthenticatedClient>());
      });

      test('sends the exchanged access token', () async {
        answerIdTokenRequests();
        answerRefreshWith(tokenResponse(accessToken: 'sb_at_oidc'));
        answerApiRequests();
        auth = buildAuth();

        await runWithOverrides(
          () => auth.client.get(Uri.parse('https://api.shorebird.dev')),
        );

        final exchange = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;
        expect(exchange[0], equals(tokenEndpoint));
        expect(exchange[1], {
          'grant_type': 'urn:ietf:params:oauth:grant-type:token-exchange',
          'subject_token_type': 'urn:ietf:params:oauth:token-type:id_token',
          'subject_token': 'gha.id',
          'audience': 'urn:shorebird:project:42',
        });
        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.BaseRequest;
        expect(request.headers['Authorization'], 'Bearer sb_at_oidc');
      });

      test('reports the exchanged token and its expiry', () async {
        answerIdTokenRequests();
        answerRefreshWith(tokenResponse(accessToken: 'sb_at_oidc'));
        auth = buildAuth();
        expect(auth.credentialKind, equals(CredentialKind.gitHubActionsOidc));

        final token = await runWithOverrides(auth.accessToken);

        expect(token, equals('sb_at_oidc'));
        expect(auth.credentialKind, equals(CredentialKind.gitHubActionsOidc));
        expect(auth.accessTokenExpiresAt, isNotNull);
      });

      test('returns a 401 challenge to its token as a response', () async {
        answerIdTokenRequests();
        answerRefreshWith(tokenResponse(accessToken: 'sb_at_oidc'));
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.unauthorized,
            headers: {'www-authenticate': 'Bearer error="invalid_token"'},
          ),
        );
        auth = buildAuth();

        final response = await runWithOverrides(
          () => auth.client.get(Uri.parse('https://api.shorebird.dev')),
        );
        expect(response.statusCode, equals(HttpStatus.unauthorized));
      });

      test('exchanges with the auth service the CLI uses', () async {
        when(
          () => shorebirdEnv.authServiceUri,
        ).thenReturn(Uri.parse('https://auth.example.com'));
        answerIdTokenRequests();
        answerRefreshWith(tokenResponse());
        answerApiRequests();
        auth = buildAuth();

        await runWithOverrides(
          () => auth.client.get(Uri.parse('https://api.shorebird.dev')),
        );

        final idTokenUrl =
            verify(
                  () => httpClient.get(
                    captureAny(),
                    headers: any(named: 'headers'),
                  ),
                ).captured.single
                as Uri;
        expect(
          idTokenUrl.queryParameters['audience'],
          'https://auth.example.com',
        );
        verify(
          () => httpClient.post(
            Uri.parse('https://auth.example.com/token'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).called(1);
      });

      test(
        'reports a refused exchange when there is no stored login',
        () async {
          answerIdTokenRequests();
          answerRefreshWith(
            oauthErrorResponse(
              'invalid_grant',
              description: 'no trust rule matches',
            ),
          );
          auth = buildAuth();

          await expectLater(
            runWithOverrides(
              () => auth.client.get(Uri.parse('https://api.shorebird.dev')),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(
            () => logger.err(
              'The Shorebird auth service refused to sign in with GitHub '
              'Actions OIDC (invalid_grant: no trust rule matches).',
            ),
          ).called(1);
          verify(
            () => logger.info(any(that: contains('trust rule'))),
          ).called(1);
          verifyNever(() => httpClient.send(any()));
        },
      );

      test(
        'reports a refused ID token request when there is no stored login',
        () async {
          when(
            () => shorebirdEnv.authServiceUri,
          ).thenReturn(Uri.parse('https://auth.example.com'));
          refuseIdTokenRequests();
          auth = buildAuth();

          await expectLater(
            runWithOverrides(
              () => auth.client.get(Uri.parse('https://api.shorebird.dev')),
            ),
            exitsWithCode(ExitCode.software),
          );

          final idTokenUrl =
              verify(
                    () => httpClient.get(
                      captureAny(),
                      headers: any(named: 'headers'),
                    ),
                  ).captured.single
                  as Uri;
          expect(
            idTokenUrl.queryParameters['audience'],
            'https://auth.example.com',
          );
          verify(
            () => logger.err(
              'GitHub Actions refused to issue an OIDC token (403).',
            ),
          ).called(1);
          verifyNever(() => httpClient.send(any()));
        },
      );

      group('with a stored login', () {
        setUp(() {
          writeCredentials();
          auth = buildAuth();
        });

        test('takes priority over it', () {
          expect(auth.isUsingGitHubActionsOidc, isTrue);
          expect(auth.email, equals(email));
        });

        test('falls back to it when the exchange is refused', () async {
          answerIdTokenRequests();
          answerRefreshWith(
            oauthErrorResponse(
              'invalid_grant',
              description: 'no trust rule matches',
            ),
          );
          answerApiRequests();

          await runWithOverrides(
            () => auth.client.get(Uri.parse('https://api.shorebird.dev')),
          );

          final request =
              verify(() => httpClient.send(captureAny())).captured.single
                  as http.BaseRequest;
          expect(
            request.headers['Authorization'],
            'Bearer $shorebirdAccessToken',
          );
          verifyNever(() => logger.err(any()));
          // The credential that authenticated, not the first one tried.
          expect(auth.credentialKind, equals(CredentialKind.login));
        });

        test('does not fall back to it once OIDC has signed in', () async {
          answerIdTokenRequests();
          // Shorter than the refresh margin, so every request exchanges.
          answerRefreshWith(
            http.Response(
              jsonEncode({
                'access_token': 'sb_at_oidc',
                'token_type': 'Bearer',
                'expires_in': 30,
              }),
              HttpStatus.ok,
              headers: {'content-type': 'application/json'},
            ),
          );
          answerApiRequests();

          await runWithOverrides(
            () => auth.client.get(Uri.parse('https://api.shorebird.dev')),
          );

          answerRefreshWith(
            oauthErrorResponse(
              'invalid_grant',
              description: 'no trust rule matches',
            ),
          );
          await expectLater(
            runWithOverrides(
              () => auth.client.get(Uri.parse('https://api.shorebird.dev')),
            ),
            exitsWithCode(ExitCode.software),
          );

          final requests = verify(
            () => httpClient.send(captureAny()),
          ).captured.cast<http.BaseRequest>();
          expect(
            requests.map((request) => request.headers['Authorization']),
            ['Bearer sb_at_oidc'],
          );
          verify(
            () => logger.err(
              'The Shorebird auth service refused to sign in with GitHub '
              'Actions OIDC (invalid_grant: no trust rule matches).',
            ),
          ).called(1);
          verifyNever(
            () => logger.detail(
              any(that: contains('Trying the next way to authenticate')),
            ),
          );
        });

        test('falls back to it when signing in with OIDC fails', () async {
          refuseIdTokenRequests();
          answerApiRequests();

          await runWithOverrides(() async {
            await auth.client.get(Uri.parse('https://api.shorebird.dev'));
            await auth.client.get(Uri.parse('https://api.shorebird.dev'));
          });

          // OIDC is tried first, and not again once it has failed.
          verify(
            () => httpClient.get(any(), headers: any(named: 'headers')),
          ).called(1);
          final requests = verify(
            () => httpClient.send(captureAny()),
          ).captured.cast<http.BaseRequest>();
          expect(
            requests.map((request) => request.headers['Authorization']),
            everyElement('Bearer $shorebirdAccessToken'),
          );
          verifyNever(() => logger.err(any()));
          verify(
            () => logger.detail(
              'GitHub Actions refused to issue an OIDC token (403). Trying '
              'the next way to authenticate.',
            ),
          ).called(1);
        });
      });

      test('an empty SHOREBIRD_TOKEN is ignored', () {
        platform = platform.copyWith(
          environment: {...oidcEnvironment, shorebirdTokenEnvVar: ' '},
        );
        auth = buildAuth();
        expect(auth.isUsingApiKey, isFalse);
        expect(auth.isUsingGitHubActionsOidc, isTrue);
        verify(
          () => logger.detail(
            '[env] $shorebirdTokenEnvVar is empty, ignoring it',
          ),
        ).called(1);
      });

      test('reports valid credentials without an exchange', () async {
        auth = buildAuth();
        expect(await runWithOverrides(auth.hasValidCredentials), isTrue);
        verifyNever(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        );
      });

      for (final (description, projectId, message, skipped) in [
        (
          'missing',
          null,
          'Signing in with GitHub Actions OIDC requires SHOREBIRD_PROJECT_ID.',
          'is not set',
        ),
        (
          'blank',
          '  ',
          'Signing in with GitHub Actions OIDC requires SHOREBIRD_PROJECT_ID.',
          'is not set',
        ),
        (
          'not a project id',
          'my-project',
          'SHOREBIRD_PROJECT_ID is not a Shorebird project id, so this job '
              'cannot sign in with GitHub Actions OIDC.',
          'is not a project id',
        ),
      ]) {
        group('when SHOREBIRD_PROJECT_ID is $description', () {
          const hint =
              'Set SHOREBIRD_PROJECT_ID to the id of your project shown at '
              'https://console.shorebird.dev, or set SHOREBIRD_TOKEN to a '
              'Shorebird API key.';

          setUp(() {
            platform = platform.copyWith(
              environment: {
                for (final MapEntry(:key, :value) in oidcEnvironment.entries)
                  if (key != shorebirdProjectIdEnvVar) key: value,
                shorebirdProjectIdEnvVar: ?projectId,
              },
            );
          });

          test('does not sign in with OIDC and says why', () async {
            auth = buildAuth();
            expect(auth.isAuthenticated, isFalse);
            expect(auth.isUsingGitHubActionsOidc, isFalse);
            expect(auth.client, isNot(isA<AuthenticatedClient>()));
            expect(await runWithOverrides(auth.hasValidCredentials), isFalse);
            expect(
              auth.unavailableCredentialsReason,
              isA<CredentialSourceException>()
                  .having((e) => e.message, 'message', message)
                  .having((e) => e.hint, 'hint', hint),
            );
            verify(
              () => logger.detail(
                '[oidc] GitHub Actions OIDC is available but '
                'SHOREBIRD_PROJECT_ID $skipped; skipping',
              ),
            ).called(1);
          });

          group('with a stored login', () {
            setUp(() {
              writeCredentials();
              auth = buildAuth();
            });

            test('uses it without an exchange', () async {
              answerApiRequests();
              expect(auth.isAuthenticated, isTrue);
              expect(auth.isUsingGitHubActionsOidc, isFalse);

              await runWithOverrides(
                () => auth.client.get(Uri.parse('https://api.shorebird.dev')),
              );

              final request =
                  verify(() => httpClient.send(captureAny())).captured.single
                      as http.BaseRequest;
              expect(
                request.headers['Authorization'],
                'Bearer $shorebirdAccessToken',
              );
              verifyNever(
                () => httpClient.get(any(), headers: any(named: 'headers')),
              );
              verify(
                () => logger.detail(
                  '[oidc] GitHub Actions OIDC is available but '
                  'SHOREBIRD_PROJECT_ID $skipped; skipping',
                ),
              ).called(1);
            });

            test('says why when the stored login fails too', () async {
              storeCredentials(
                credentialsWith(refreshToken: null, expired: true),
              );
              auth = buildAuth();

              await expectLater(
                runWithOverrides(
                  () => auth.client.get(Uri.parse('https://api.shorebird.dev')),
                ),
                exitsWithCode(ExitCode.software),
              );
              verifyInOrder([
                () => logger.err('Your Shorebird login has expired.'),
                () => logger.info(
                  'Run ${lightCyan.wrap('shorebird login')} to log in again.',
                ),
                () => logger.info(message),
                () => logger.info(hint),
              ]);
              verifyNever(
                () => httpClient.get(any(), headers: any(named: 'headers')),
              );
            });
          });
        });
      }

      group('when SHOREBIRD_TOKEN is set', () {
        setUp(() {
          platform = platform.copyWith(
            environment: {
              ...oidcEnvironment,
              shorebirdTokenEnvVar: 'sb_api_x',
            },
          );
          auth = buildAuth();
        });

        test('it takes priority, without an exchange', () async {
          answerApiRequests();
          expect(auth.isUsingApiKey, isTrue);
          expect(auth.isUsingGitHubActionsOidc, isFalse);

          await runWithOverrides(
            () => auth.client.get(Uri.parse('https://api.shorebird.dev')),
          );
          final request =
              verify(() => httpClient.send(captureAny())).captured.single
                  as http.BaseRequest;
          expect(request.headers['Authorization'], 'Bearer sb_api_x');
          verifyNever(
            () => httpClient.get(any(), headers: any(named: 'headers')),
          );
          verifyNever(
            () => httpClient.post(
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          );
        });

        test('suggests GitHub Actions OIDC once', () {
          verify(
            () => logger.info(
              'This job can sign in with GitHub Actions OIDC instead: add a '
              'GitHub Actions trust rule at https://console.shorebird.dev, '
              'set SHOREBIRD_PROJECT_ID to the id of its project, and remove '
              'SHOREBIRD_TOKEN to stop storing a long-lived secret.',
            ),
          ).called(1);
        });
      });
    });

    group('when GitHub Actions grants no OIDC token request', () {
      setUp(() {
        platform = platform.copyWith(
          environment: {githubActionsEnvVar: 'true'},
        );
      });

      test('is not authenticated', () {
        auth = buildAuth();
        expect(auth.isAuthenticated, isFalse);
        expect(auth.isUsingGitHubActionsOidc, isFalse);
      });

      test('treats an empty SHOREBIRD_TOKEN as unset', () {
        platform = platform.copyWith(
          environment: {githubActionsEnvVar: 'true', shorebirdTokenEnvVar: ''},
        );
        auth = buildAuth();
        expect(auth.isAuthenticated, isFalse);
        expect(auth.isUsingApiKey, isFalse);
      });
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
            environment: {shorebirdTokenEnvVar: 'sb_api_abc123'},
          );
          auth = buildAuth();
        });

        test('returns true without refreshing', () async {
          expect(await runWithOverrides(auth.hasValidCredentials), isTrue);
        });
      });

      group('when stored credentials can be refreshed', () {
        setUp(() {
          writeCredentials();
          answerRefreshWith(tokenResponse());
          auth = buildAuth();
        });

        test('refreshes and persists the refreshed credentials, even though '
            'the access token is current', () async {
          expect(await runWithOverrides(auth.hasValidCredentials), isTrue);
          expect(auth.email, equals(email));
          expect(
            readStoredCredentials().refreshToken,
            equals('sb_rt_rotated'),
          );
          // The refresh keeps the email stored with the login.
          expect(readStoredEmail(), equals(email));
        });
      });

      test('returns false with no refresh token', () async {
        storeCredentials(credentialsWith(refreshToken: null));
        auth = buildAuth();
        expect(await runWithOverrides(auth.hasValidCredentials), isFalse);
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
        ]) {
          test('returns false for a $status $code', () async {
            answerRefreshWith(oauthErrorResponse(code, status: status));
            auth = buildAuth();
            expect(await runWithOverrides(auth.hasValidCredentials), isFalse);
          });
        }
      });

      // Answering false here would log the user out over a bad connection,
      // which is not what a failure to get an OAuth answer means.
      group('when the auth service gives no OAuth answer', () {
        setUp(writeCredentials);

        for (final (description, response) in [
          ('a 429', http.Response('', HttpStatus.tooManyRequests)),
          ('a 5xx', http.Response('bad gateway', HttpStatus.badGateway)),
          (
            'a 4xx that is not an OAuth error response',
            http.Response('Unauthorized', HttpStatus.unauthorized),
          ),
          ('a 200 that is not a token response', http.Response('ok', 200)),
        ]) {
          test('rethrows $description', () async {
            answerRefreshWith(response);
            auth = buildAuth();
            await expectLater(
              runWithOverrides(auth.hasValidCredentials),
              throwsA(isA<FormatException>()),
            );
            expect(readStoredCredentials().refreshToken, equals(refreshToken));
          });
        }

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
      // An access token told apart from the others by [name].
      String accessTokenNamed(String name) => 'sb_at_$name';

      oauth2.Credentials credentialsNamed(
        String name, {
        required String refreshToken,
        required bool expired,
      }) {
        return credentialsWith(
          accessToken: accessTokenNamed(name),
          refreshToken: refreshToken,
          expired: expired,
        );
      }

      // The refresh tokens presented to the auth service, in order.
      late List<String?> presentedRefreshTokens;
      // The access tokens sent to the API, in order.
      late List<String?> sentAccessTokens;

      setUp(() {
        presentedRefreshTokens = [];
        sentAccessTokens = [];
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((invocation) async {
          final body = invocation.namedArguments[#body] as Map;
          presentedRefreshTokens.add(body['refresh_token'] as String?);
          return tokenResponse(accessToken: accessTokenNamed('rotated'));
        });
        when(() => httpClient.send(any())).thenAnswer((invocation) async {
          final request =
              invocation.positionalArguments.first as http.BaseRequest;
          sentAccessTokens.add(
            request.headers['authorization']?.replaceFirst('Bearer ', ''),
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
        expect(stored.accessToken, equals(accessTokenNamed('rotated')));
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
            equals(['credentials-v2.json']),
          );
          expect(readStoredCredentials().refreshToken, equals('sb_rt_rotated'));
        },
      );

      test('refreshes with the credentials in memory when the file is '
          'gone', () async {
        final auth = buildAuth();
        File(credentialsPath).deleteSync();

        await sendRequest(auth);

        expect(presentedRefreshTokens, equals([refreshToken]));
        expect(sentAccessTokens, equals([accessTokenNamed('rotated')]));
        expect(readStoredCredentials().refreshToken, equals('sb_rt_rotated'));
      });

      test('carries on with the refreshed credentials and warns when they '
          'cannot be saved', () async {
        final auth = buildAuth();
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
          equals(['credentials-v2.json']),
        );
      });

      test(
        'saves the refreshed credentials while another process has the '
        'file open',
        () async {
          final auth = buildAuth();
          final open = File(credentialsPath).openSync();
          try {
            await sendRequest(auth);
          } finally {
            open.closeSync();
          }

          expect(readStoredCredentials().refreshToken, equals('sb_rt_rotated'));
          expect(
            Directory(credentialsDir).listSync().map((e) => p.basename(e.path)),
            equals(['credentials-v2.json']),
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
          final credentialsFile = File(credentialsPath)..writeAsStringSync('');
          // Start from a world-readable file.
          Process.runSync('chmod', ['644', credentialsFile.path]);
          auth = buildAuth();

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

      test('obtains the credentials with the shorebird User-Agent', () async {
        await runWithOverrides(() => auth.login(prompt: (_) {}));
        expect(loginHttpClient, isA<UserAgentClient>());
      });

      test('stores the credentials and sets the email', () async {
        await runWithOverrides(() => auth.login(prompt: (_) {}));
        expect(auth.email, email);
        expect(auth.isAuthenticated, isTrue);
        expect(readStoredCredentials().toJson(), accessCredentials.toJson());
        expect(readStoredEmail(), equals(email));
        expect(buildAuth().email, email);
        expect(buildAuth().isAuthenticated, isTrue);
      });

      test(
        'throws UserAlreadyLoggedInException if user is authenticated',
        () async {
          writeCredentials();
          auth = buildAuth();

          await expectLater(
            runWithOverrides(() => auth.login(prompt: (_) {})),
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
            environment: {shorebirdTokenEnvVar: 'sb_api_abc123'},
          );
          auth = buildAuth();

          await expectLater(
            runWithOverrides(() => auth.login(prompt: (_) {})),
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

      test('proceeds when stored credentials are corrupted', () async {
        File(credentialsPath).writeAsStringSync('corrupted');
        auth = buildAuth();
        expect(auth.email, isNull);

        await runWithOverrides(() => auth.login(prompt: (_) {}));

        expect(auth.email, equals(email));
        expect(auth.isAuthenticated, isTrue);
      });

      test('should not set the email when user does not exist', () async {
        when(
          () => codePushClient.getCurrentUser(),
        ).thenAnswer((_) async => null);

        await expectLater(
          runWithOverrides(() => auth.login(prompt: (_) {})),
          throwsA(isA<UserNotFoundException>()),
        );

        expect(auth.email, isNull);
        expect(auth.isAuthenticated, isFalse);
        expect(File(credentialsPath).existsSync(), isFalse);
      });
    });

    group('loginWithDeviceCode', () {
      test('obtains the credentials with the shorebird User-Agent', () async {
        await runWithOverrides(
          () => auth.loginWithDeviceCode(prompt: (_) {}),
        );
        expect(loginHttpClient, isA<UserAgentClient>());
      });

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
        expect(readStoredCredentials().toJson(), accessCredentials.toJson());
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

    group('fetchEmail', () {
      Future<String?> fetchEmail() => runWithOverrides(auth.fetchEmail);

      test('returns the stored email without asking the API', () async {
        writeCredentials();
        auth = buildAuth();

        expect(await fetchEmail(), equals(email));
        verifyNever(() => codePushClient.getCurrentUser());
      });

      test('returns null when not logged in', () async {
        expect(await fetchEmail(), isNull);
        verifyNever(() => codePushClient.getCurrentUser());
      });

      test('returns null when authenticated via API key', () async {
        platform = platform.copyWith(
          environment: {shorebirdTokenEnvVar: 'sb_api_abc123'},
        );
        auth = buildAuth();

        expect(await fetchEmail(), isNull);
        verifyNever(() => codePushClient.getCurrentUser());
      });

      group('when the credentials were stored without an email', () {
        setUp(() {
          storeCredentials(accessCredentials);
          auth = buildAuth();
        });

        test('fetches the user and stores the email', () async {
          expect(await fetchEmail(), equals(email));
          expect(auth.email, equals(email));
          expect(readStoredEmail(), equals(email));
          expect(readStoredCredentials().toJson(), accessCredentials.toJson());
          expect(buildAuth().email, equals(email));

          // Once known, it is not fetched again.
          expect(await fetchEmail(), equals(email));
          verify(() => codePushClient.getCurrentUser()).called(1);
        });

        test('returns null when the user cannot be fetched', () async {
          when(
            () => codePushClient.getCurrentUser(),
          ).thenThrow(Exception('offline'));

          expect(await fetchEmail(), isNull);
          expect(auth.isAuthenticated, isTrue);
          expect(readStoredEmail(), isNull);
          verify(
            () => logger.detail(any(that: contains('offline'))),
          ).called(1);
        });

        test('returns null when there is no such user', () async {
          when(
            () => codePushClient.getCurrentUser(),
          ).thenAnswer((_) async => null);

          expect(await fetchEmail(), isNull);
          expect(readStoredEmail(), isNull);
        });

        test('leaves a newer login another process stored alone', () async {
          storeCredentials(credentialsWith(accessToken: 'sb_at_newer'));

          expect(await fetchEmail(), equals(email));
          expect(readStoredCredentials().accessToken, equals('sb_at_newer'));
          expect(readStoredEmail(), isNull);
        });

        test('leaves the file alone when the login was removed', () async {
          File(credentialsPath).deleteSync();

          expect(await fetchEmail(), equals(email));
          expect(File(credentialsPath).existsSync(), isFalse);
        });

        test(
          'returns the email when it cannot be stored',
          () async {
            Process.runSync('chmod', ['500', credentialsDir]);
            addTearDown(
              () => Process.runSync('chmod', ['700', credentialsDir]),
            );

            expect(await fetchEmail(), equals(email));
            verify(
              () => logger.detail(
                any(that: contains('Could not save your email')),
              ),
            ).called(1);
          },
          skip: io.Platform.isWindows
              ? 'Windows has no POSIX file modes.'
              : false,
        );
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
        await runWithOverrides(() => auth.login(prompt: (_) {}));
        expect(auth.isAuthenticated, isTrue);
        expect(File(credentialsPath).existsSync(), isTrue);

        await runWithOverrides(auth.logout);
        expect(auth.email, isNull);
        expect(auth.isAuthenticated, isFalse);
        expect(auth.client, same(httpClient));
        expect(File(credentialsPath).existsSync(), isFalse);
        expect(buildAuth().isAuthenticated, isFalse);
      });

      test('deletes a legacy credentials file an older CLI wrote', () async {
        writeCredentials();
        File(legacyCredentialsPath).writeAsStringSync('{}');
        auth = buildAuth();

        await runWithOverrides(auth.logout);

        expect(File(credentialsPath).existsSync(), isFalse);
        expect(File(legacyCredentialsPath).existsSync(), isFalse);
      });

      group('when authenticated via API key', () {
        setUp(() {
          platform = platform.copyWith(
            environment: {shorebirdTokenEnvVar: 'sb_api_abc123'},
          );
          auth = buildAuth();
        });

        test('remains authenticated because env var is still set', () async {
          expect(auth.isAuthenticated, isTrue);
          await runWithOverrides(auth.logout);
          // _apiKey is not cleared by clearCredentials, so the instance
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
        await runWithOverrides(() => auth.login(prompt: (_) {}));

        expect(await runWithOverrides(auth.logout), isTrue);

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
          await runWithOverrides(() => auth.login(prompt: (_) {}));
          stubRevocation(
            () async => http.Response(
              '{"error":"internal_error"}',
              HttpStatus.internalServerError,
            ),
          );

          expect(await runWithOverrides(auth.logout), isFalse);
          expect(auth.isAuthenticated, isFalse);
          expect(File(credentialsPath).existsSync(), isFalse);
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
          await runWithOverrides(() => auth.login(prompt: (_) {}));
          stubRevocation(
            () async => throw const SocketException('no internet'),
          );

          expect(await runWithOverrides(auth.logout), isFalse);
          expect(auth.email, isNull);
          expect(auth.isAuthenticated, isFalse);
          expect(File(credentialsPath).existsSync(), isFalse);
          verify(
            () => logger.detail(any(that: contains('no internet'))),
          ).called(1);
        },
      );

      test('skips revocation when no refresh token', () async {
        storeCredentials(credentialsWith(refreshToken: null));
        auth = buildAuth();

        expect(await runWithOverrides(auth.logout), isTrue);

        verifyNever(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        );
        expect(File(credentialsPath).existsSync(), isFalse);
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

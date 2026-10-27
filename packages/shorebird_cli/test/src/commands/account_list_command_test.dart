import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/browser.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/account_list_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(AccountListCommand, () {
    final consoleUrl = Uri.parse(
      'https://console.shorebird.dev/account/api-keys',
    );
    final apiUrl = Uri.parse('https://auth.shorebird.dev/api/api-keys');

    late Auth auth;
    late Browser browser;
    late CodePushClient codePushClient;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late AccountListCommand command;

    R runWithOverrides<R>(R Function() body, {bool jsonMode = false}) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          browserRef.overrideWith(() => browser),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => jsonMode),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    void respond(int status, Object body) {
      when(() => codePushClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(utf8.encode(body is String ? body : jsonEncode(body))),
          status,
        ),
      );
    }

    setUpAll(() {
      registerFallbackValue(Uri());
      registerFallbackValue(http.Request('GET', Uri()));
    });

    setUp(() {
      auth = MockAuth();
      browser = MockBrowser();
      codePushClient = MockCodePushClient();
      codePushClientWrapper = MockCodePushClientWrapper();
      shorebirdEnv = MockShorebirdEnv();
      logger = MockShorebirdLogger();
      shorebirdValidator = MockShorebirdValidator();
      when(() => auth.credentialKind).thenReturn(CredentialKind.login);
      when(() => browser.canOpen).thenReturn(true);
      when(() => browser.open(any())).thenAnswer((_) async => true);
      when(
        () => codePushClientWrapper.codePushClient,
      ).thenReturn(codePushClient);
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
      when(
        () => shorebirdEnv.authServiceUri,
      ).thenReturn(Uri.parse('https://auth.shorebird.dev'));
      when(
        () => shorebirdEnv.hostedEnvironment,
      ).thenReturn(productionEnvironment);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      command = AccountListCommand(
        name: 'list',
        commandLine: 'shorebird tokens list',
        lead: 'List your API keys.',
        apiPath: 'api/api-keys',
        listKey: 'api_keys',
        consolePath: 'account/api-keys',
        action: 'see your API keys',
        manage: 'Create or revoke a key',
        none: 'No API keys.',
        describe: (key) => 'key ${key['id']}',
      );
    });

    test('describes what it lists and the --json form', () {
      expect(
        command.description,
        allOf(
          startsWith('List your API keys.'),
          contains('shorebird tokens list --json'),
        ),
      );
    });

    test('prints each entry, then where to change them', () async {
      respond(200, {
        'api_keys': [
          {'id': '1'},
          {'id': '2'},
        ],
      });
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      final request =
          verify(() => codePushClient.send(captureAny())).captured.single
              as http.Request;
      expect(request.method, 'GET');
      expect(request.url, apiUrl);
      verify(() => logger.info('key 1')).called(1);
      verify(() => logger.info('key 2')).called(1);
      verify(
        () => logger.info(
          any(
            that: allOf(
              contains('Create or revoke a key at'),
              contains('$consoleUrl'),
            ),
          ),
        ),
      ).called(1);
      verifyNever(() => browser.open(any()));
    });

    test('says when there are none', () async {
      respond(200, {'api_keys': <Object>[]});
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(() => logger.info('No API keys.')).called(1);
    });

    test('reports the list under --json', () async {
      respond(200, {
        'api_keys': [
          {'id': '1', 'name': 'ci'},
        ],
      });
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, jsonMode: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {
        'api_keys': [
          {'id': '1', 'name': 'ci'},
        ],
      });
    });

    for (final status in [401, 403]) {
      test('opens the console when the auth service answers $status', () async {
        respond(status, {'error': 'unauthorized'});
        expect(await runWithOverrides(command.run), ExitCode.success.code);
        verify(() => browser.open(consoleUrl)).called(1);
      });
    }

    for (final kind in [
      CredentialKind.apiKey,
      CredentialKind.gitHubActionsOidc,
    ]) {
      test('opens the console, sending nothing, with ${kind.name}', () async {
        when(() => auth.credentialKind).thenReturn(kind);
        expect(await runWithOverrides(command.run), ExitCode.success.code);
        verify(() => browser.open(consoleUrl)).called(1);
        verifyNever(() => codePushClient.send(any()));
      });
    }

    test('fails on an unexpected response', () async {
      respond(500, 'oops');
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, jsonMode: true),
      );
      expect(exitCode, isNot(ExitCode.success.code));
      final error = json['error'] as Map<String, dynamic>;
      expect(error['code'], 'fetch_failed');
      expect(error['message'], contains('HTTP 500'));
      expect(error['hint'], contains('$consoleUrl'));
    });

    test('fails when the request cannot be sent', () async {
      when(
        () => codePushClient.send(any()),
      ).thenThrow(http.ClientException('offline'));
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, jsonMode: true),
      );
      expect(exitCode, isNot(ExitCode.success.code));
      expect((json['error'] as Map)['code'], 'fetch_failed');
    });

    test('stops when not signed in', () async {
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenThrow(UserNotAuthorizedException());
      expect(await runWithOverrides(command.run), ExitCode.noUser.code);
      verifyNever(() => codePushClient.send(any()));
    });
  });

  test('accountListDate formats a timestamp as its UTC date', () {
    expect(accountListDate('2026-10-27T23:30:00-05:00'), '2026-10-28');
    expect(accountListDate(null), 'never');
    expect(accountListDate('nope', otherwise: '-'), '-');
  });
}

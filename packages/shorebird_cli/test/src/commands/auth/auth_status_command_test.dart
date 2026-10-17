import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/auth/auth.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(AuthStatusCommand, () {
    const user = PrivateUser(
      id: 42,
      email: 'user@example.com',
      jwtIssuer: 'https://auth.shorebird.dev',
    );
    final expiresAt = DateTime.utc(2026, 10, 17, 1);

    late Auth auth;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late AuthStatusCommand command;

    R runWithOverrides<R>(R Function() body, {bool json = false}) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => json),
          loggerRef.overrideWith(() => logger),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      auth = MockAuth();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      shorebirdValidator = MockShorebirdValidator();
      command = AuthStatusCommand();

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getCurrentUser(),
      ).thenAnswer((_) async => user);
      when(() => auth.credentialKind).thenReturn(CredentialKind.login);
      when(() => auth.accessTokenExpiresAt).thenReturn(expiresAt);
    });

    test('has a description naming the order credentials are tried', () {
      expect(command.name, equals('status'));
      expect(command.description, contains('SHOREBIRD_TOKEN'));
    });

    test('requires the user to be authenticated', () async {
      await runWithOverrides(command.run);
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
        ),
      ).called(1);
    });

    test('returns the precondition exit code when not authenticated', () async {
      final exception = UserNotAuthorizedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenThrow(exception);
      final result = await runWithOverrides(command.run);
      expect(result, equals(exception.exitCode.code));
    });

    test('prints the credential, user and expiry', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(
        () => logger.info('Credential:  Login (shorebird login)'),
      ).called(1);
      verify(
        () => logger.info('Acting as:   user@example.com (ID 42)'),
      ).called(1);
      verify(
        () => logger.info('Expires:     2026-10-17T01:00:00.000Z'),
      ).called(1);
    });

    test('leaves out the expiry for an API key', () async {
      when(() => auth.credentialKind).thenReturn(CredentialKind.apiKey);
      when(() => auth.accessTokenExpiresAt).thenReturn(null);
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(
        () => logger.info('Credential:  API key (SHOREBIRD_TOKEN)'),
      ).called(1);
      verifyNever(() => logger.info(any(that: startsWith('Expires'))));
    });

    test('says unknown when the credential is not known', () async {
      when(() => auth.credentialKind).thenReturn(null);
      await runWithOverrides(command.run);
      verify(() => logger.info('Credential:  unknown')).called(1);
    });

    test('emits the status as JSON', () async {
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, equals(ExitCode.success.code));
      expect(json['data'], {
        'credential': 'login',
        'user': {'id': 42, 'email': 'user@example.com'},
        'expires_at': '2026-10-17T01:00:00.000Z',
      });
    });

    test('emits a JSON error when the user cannot be fetched', () async {
      when(
        () => codePushClientWrapper.getCurrentUser(),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, equals(ExitCode.software.code));
      expect(json['error'], {
        'code': 'fetch_failed',
        'message': 'Failed to fetch account.',
      });
    });
  });
}

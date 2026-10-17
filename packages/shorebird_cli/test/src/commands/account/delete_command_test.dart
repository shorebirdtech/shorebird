import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/account/delete_command.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(AccountDeleteCommand, () {
    const email = 'user@example.com';
    const user = PrivateUser(
      id: 42,
      email: email,
      jwtIssuer: 'https://auth.shorebird.dev',
    );

    late ArgResults argResults;
    late Auth auth;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late AccountDeleteCommand command;

    R runWithOverrides<R>(R Function() body, {bool json = false}) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => json),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    void verifyNeverDeleted() {
      verifyNever(() => codePushClientWrapper.deleteCurrentUser());
    }

    setUp(() {
      argResults = MockArgResults();
      auth = MockAuth();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();
      command = runWithOverrides(AccountDeleteCommand.new)
        ..testArgResults = argResults;

      when(() => argResults['confirm-name']).thenReturn(email);
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getCurrentUser(),
      ).thenAnswer((_) async => user);
      when(
        () => codePushClientWrapper.deleteCurrentUser(),
      ).thenAnswer((_) async {});
      when(() => auth.credentialKind).thenReturn(CredentialKind.login);
    });

    test('has a name, and only --confirm-name to confirm', () {
      expect(command.name, equals('delete'));
      expect(command.description, contains('cannot be undone'));
      expect(command.argParser.options.keys, contains('confirm-name'));
      expect(command.argParser.options.keys, isNot(contains('yes')));
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
      verifyNeverDeleted();
    });

    test('deletes the account and logs out a stored login', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(() => codePushClientWrapper.deleteCurrentUser()).called(1);
      verify(() => auth.clearCredentials()).called(1);
      verify(
        () => logger.success('Deleted the Shorebird account $email.'),
      ).called(1);
      verify(() => logger.info('You are now logged out.')).called(1);
    });

    test('leaves an API key alone', () async {
      when(() => auth.credentialKind).thenReturn(CredentialKind.apiKey);
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verifyNever(() => auth.clearCredentials());
      verifyNever(() => logger.info('You are now logged out.'));
    });

    test('refuses a --confirm-name that is not the email', () async {
      when(() => argResults['confirm-name']).thenReturn('other@example.com');
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.usage.code));
      verifyNeverDeleted();
    });

    test('requires --confirm-name when it cannot prompt', () async {
      when(() => argResults['confirm-name']).thenReturn(null);
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.usage.code));
      verify(
        () => logger.info(
          'Re-run with --confirm-name "$email" to delete '
          'your Shorebird account ($email).',
        ),
      ).called(1);
      verifyNeverDeleted();
    });

    group('in a terminal', () {
      setUp(() {
        when(() => argResults['confirm-name']).thenReturn(null);
        when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
      });

      test(
        'states the consequence, asks for the email, then deletes',
        () async {
          when(
            () => logger.prompt(any(), hint: any(named: 'hint')),
          ).thenReturn(email);
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verifyInOrder([
            () =>
                logger.info(any(that: startsWith('This permanently deletes'))),
            () => logger.prompt(
              'Type $email to confirm deletion:',
              hint: any(named: 'hint'),
            ),
            () => codePushClientWrapper.deleteCurrentUser(),
            () => auth.clearCredentials(),
          ]);
        },
      );

      test('deletes nothing when the typed email does not match', () async {
        when(
          () => logger.prompt(any(), hint: any(named: 'hint')),
        ).thenReturn('other@example.com');
        await expectLater(
          runWithOverrides(command.run),
          throwsA(isA<PromptDeclinedExit>()),
        );
        verifyNeverDeleted();
        verifyNever(() => auth.clearCredentials());
      });
    });

    test('reports a refusal from the server with its code', () async {
      const error = CodePushException(
        message: 'You own team organizations: Acme.',
        statusCode: 409,
        response: ErrorResponse(
          code: 'user_delete_blocked_by_team_orgs',
          message: 'You own team organizations: Acme.',
        ),
      );
      when(
        () => codePushClientWrapper.deleteCurrentUser(),
      ).thenThrow(ApiErrorExit(error, ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, equals(ExitCode.software.code));
      final jsonError = json['error'] as Map<String, dynamic>;
      expect(jsonError['code'], equals('software_error'));
      expect(jsonError['api_code'], equals('user_delete_blocked_by_team_orgs'));
      expect(jsonError['message'], contains('You own team organizations'));
      verifyNever(() => auth.clearCredentials());
    });

    test('emits the deleted account as JSON', () async {
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, equals(ExitCode.success.code));
      expect(json['data'], {
        'user': {'id': 42, 'email': email},
        'deleted': true,
        'logged_out': true,
      });
    });

    test('emits fetch_failed when the account cannot be fetched', () async {
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
      verifyNeverDeleted();
    });

    test('keeps the login when the delete fails', () async {
      when(
        () => codePushClientWrapper.deleteCurrentUser(),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, equals(ExitCode.software.code));
      expect(json['error'], {
        'code': 'software_error',
        'message': 'Failed to delete your account.',
      });
      verifyNever(() => auth.clearCredentials());
    });
  });
}

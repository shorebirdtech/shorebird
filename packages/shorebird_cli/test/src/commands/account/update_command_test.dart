import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/account/update_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(AccountUpdateCommand, () {
    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late AccountUpdateCommand command;

    R runWithOverrides<R>(R Function() body, {bool json = false}) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => json),
          loggerRef.overrideWith(() => logger),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      shorebirdValidator = MockShorebirdValidator();
      command = AccountUpdateCommand()..testArgResults = argResults;

      when(() => argResults['name']).thenReturn('Jane Doe');
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.updateCurrentUser(
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) async {});
    });

    test('has a name and description', () {
      expect(command.name, equals('update'));
      expect(command.description, contains('--name'));
    });

    test('fails without --name, before any request', () async {
      when(() => argResults['name']).thenReturn(null);
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err('Nothing to update: pass --name.')).called(1);
      verifyNever(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      );
    });

    test('fails with a blank --name', () async {
      when(() => argResults['name']).thenReturn('  ');
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.usage.code));
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

    test('sets the display name', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(
        () => codePushClientWrapper.updateCurrentUser(displayName: 'Jane Doe'),
      ).called(1);
      verify(
        () => logger.success('Your display name is now "Jane Doe".'),
      ).called(1);
    });

    test('emits the new display name as JSON', () async {
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, equals(ExitCode.success.code));
      expect(json['data'], {
        'user': {'display_name': 'Jane Doe'},
      });
    });

    test('emits a JSON error when the update fails', () async {
      when(
        () => codePushClientWrapper.updateCurrentUser(
          displayName: any(named: 'displayName'),
        ),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, equals(ExitCode.software.code));
      expect(json['error'], {
        'code': 'software_error',
        'message': 'Failed to update your account.',
      });
    });
  });
}

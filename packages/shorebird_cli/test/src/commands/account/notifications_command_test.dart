import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/account/notifications_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(AccountNotificationsCommand, () {
    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdLogger logger;
    late ShorebirdValidator shorebirdValidator;
    late AccountNotificationsCommand command;

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
      command = AccountNotificationsCommand()..testArgResults = argResults;

      when(() => argResults['email']).thenReturn(null);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.getEmailNotificationsEnabled(),
      ).thenAnswer((_) async => true);
      when(
        () => codePushClientWrapper.setEmailNotificationsEnabled(
          enabled: any(named: 'enabled'),
        ),
      ).thenAnswer((_) async {});
    });

    test('has a name and description', () {
      expect(command.name, equals('notifications'));
      expect(command.description, contains('--email off'));
      expect(command.argParser.options['email']!.allowed, ['on', 'off']);
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

    group('with no options', () {
      test('shows the setting', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(() => logger.info('Email notifications: on')).called(1);
        verifyNever(
          () => codePushClientWrapper.setEmailNotificationsEnabled(
            enabled: any(named: 'enabled'),
          ),
        );
      });

      test('shows the setting as JSON', () async {
        when(
          () => codePushClientWrapper.getEmailNotificationsEnabled(),
        ).thenAnswer((_) async => false);
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, equals(ExitCode.success.code));
        expect(json['data'], {'email': false});
      });

      test('emits fetch_failed when the setting cannot be read', () async {
        when(
          () => codePushClientWrapper.getEmailNotificationsEnabled(),
        ).thenThrow(ProcessExit(ExitCode.software.code));
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, equals(ExitCode.software.code));
        expect(json['error'], {
          'code': 'fetch_failed',
          'message': 'Failed to fetch your notification settings.',
        });
      });
    });

    group('with --email off', () {
      setUp(() {
        when(() => argResults['email']).thenReturn('off');
      });

      test('turns email notifications off', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => codePushClientWrapper.setEmailNotificationsEnabled(
            enabled: false,
          ),
        ).called(1);
        verify(
          () => logger.success('Email notifications are now off.'),
        ).called(1);
        verifyNever(() => codePushClientWrapper.getEmailNotificationsEnabled());
      });

      test('emits software_error when the update fails', () async {
        when(
          () => codePushClientWrapper.setEmailNotificationsEnabled(
            enabled: any(named: 'enabled'),
          ),
        ).thenThrow(ProcessExit(ExitCode.software.code));
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, json: true),
        );
        expect(exitCode, equals(ExitCode.software.code));
        expect(json['error'], {
          'code': 'software_error',
          'message': 'Failed to update your notification settings.',
        });
      });
    });

    test('--email on turns them on, reported as JSON', () async {
      when(() => argResults['email']).thenReturn('on');
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, json: true),
      );
      expect(exitCode, equals(ExitCode.success.code));
      expect(json['data'], {'email': true});
      verify(
        () => codePushClientWrapper.setEmailNotificationsEnabled(enabled: true),
      ).called(1);
    });
  });
}

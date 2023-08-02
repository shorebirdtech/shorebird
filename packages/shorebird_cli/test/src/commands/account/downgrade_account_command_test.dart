import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/account/account.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

void main() {
  group(DowngradeAccountCommand, () {
    const noSubscriptionUser = User(id: 1, email: 'tester1@shorebird.dev');
    const subscriptionUser = User(
      id: 2,
      email: 'tester2@shorebird.dev',
      hasActiveSubscription: true,
    );

    late CodePushClientWrapper codePushClientWrapper;
    late CodePushClient codePushClient;
    late Logger logger;
    late Progress progress;
    late ShorebirdValidator shorebirdValidator;
    late DowngradeAccountCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          loggerRef.overrideWith(() => logger),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      codePushClientWrapper = _MockCodePushClientWrapper();
      codePushClient = _MockCodePushClient();
      logger = _MockLogger();
      progress = _MockProgress();
      shorebirdValidator = _MockShorebirdValidator();

      when(
        () => codePushClientWrapper.codePushClient,
      ).thenReturn(codePushClient);
      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(DowngradeAccountCommand.new);
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    test('exits when validation fails', () async {
      final exception = ValidationFailedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenThrow(exception);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(exception.exitCode.code)),
      );
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
        ),
      ).called(1);
    });

    test('prints an error if fetch current user fails', () async {
      when(() => codePushClient.getCurrentUser()).thenThrow(
        Exception('an error occurred'),
      );

      final result = await runWithOverrides(command.run);

      expect(result, ExitCode.software.code);
      verify(
        () => logger.err(any(that: contains('an error occurred'))),
      ).called(1);
    });

    test('prints an error if fetch current user returns null', () async {
      when(() => codePushClient.getCurrentUser()).thenAnswer((_) async => null);

      final result = await runWithOverrides(command.run);

      expect(result, ExitCode.software.code);
      verify(
        () => logger.err(
          any(that: contains('Failed to retrieve user information')),
        ),
      ).called(1);
    });

    test(
      'prints an error if the user does not have an active subscription',
      () async {
        when(
          () => codePushClient.getCurrentUser(),
        ).thenAnswer((_) async => noSubscriptionUser);

        final result = await runWithOverrides(command.run);

        expect(result, ExitCode.software.code);
        verify(
          () => logger.err(
            any(that: contains('You do not have a "teams" subscription')),
          ),
        ).called(1);
      },
    );

    test('exits successfully if the user opts not to cancel', () async {
      when(
        () => codePushClient.getCurrentUser(),
      ).thenAnswer((_) async => subscriptionUser);
      when(
        () => logger.confirm(any(that: contains('Are you sure?'))),
      ).thenReturn(false);

      final result = await runWithOverrides(command.run);

      expect(result, ExitCode.success.code);
      verify(() => logger.info('Aborting.')).called(1);
    });

    test('prints an error if call to cancel subscription fails', () async {
      when(
        () => codePushClient.getCurrentUser(),
      ).thenAnswer((_) async => subscriptionUser);
      when(
        () => logger.confirm(any(that: contains('Are you sure?'))),
      ).thenReturn(true);
      when(() => codePushClient.cancelSubscription()).thenThrow(
        Exception('an error occurred'),
      );

      final result = await runWithOverrides(command.run);

      expect(result, ExitCode.software.code);
      verify(
        () => progress.fail(any(that: contains('an error occurred'))),
      ).called(1);
    });

    test('exits successfully on subscription cancellation', () async {
      // Fri Apr 14 2023 07:00:00 GMT+0000
      const cancellationTimestamp = 1681455600;
      when(
        () => codePushClient.getCurrentUser(),
      ).thenAnswer((_) async => subscriptionUser);
      when(
        () => logger.confirm(any(that: contains('Are you sure?'))),
      ).thenReturn(true);

      when(() => codePushClient.cancelSubscription()).thenAnswer(
        (_) async => DateTime.fromMillisecondsSinceEpoch(
          cancellationTimestamp * 1000,
        ),
      );

      final result = await runWithOverrides(command.run);

      expect(result, ExitCode.success.code);

      verify(
        () => progress.complete(
          any(
            that: stringContainsInOrder([
              'Your plan has been downgraded.',
              '''Note: Your current plan will continue until April 14, 2023, after which your account will be on the "hobby" tier.'''
            ]),
          ),
        ),
      ).called(1);
    });
  });
}

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/subscription/cancel_subscription_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

void main() {
  group('CancelSubscriptionCommand', () {
    const noSubscriptionUser = User(id: 1, email: 'tester1@shorebird.dev');
    const subscriptionUser = User(
      id: 2,
      email: 'tester2@shorebird.dev',
      hasActiveSubscription: true,
    );

    late Auth auth;
    late CodePushClient codePushClient;
    late http.Client httpClient;
    late Logger logger;
    late Progress progress;

    late CancelSubscriptionCommand command;

    setUp(() {
      auth = _MockAuth();
      codePushClient = _MockCodePushClient();
      httpClient = _MockHttpClient();
      logger = _MockLogger();
      progress = _MockProgress();

      command = CancelSubscriptionCommand(
        logger: logger,
        auth: auth,
        buildCodePushClient: ({
          required http.Client httpClient,
          Uri? hostedUri,
        }) =>
            codePushClient,
      );

      when(() => auth.client).thenReturn(httpClient);

      when(() => logger.progress(any())).thenReturn(progress);
    });

    test('returns a non-empty description', () {
      expect(command.description, isNotEmpty);
    });

    test('prints an error if the user is not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);

      final result = await command.run();

      expect(result, ExitCode.noUser.code);
      verify(
        () => logger.err(any(that: contains('You must be logged in'))),
      ).called(1);
    });

    test('prints an error if fetch current user fails', () async {
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => codePushClient.getCurrentUser()).thenThrow(
        Exception('an error occurred'),
      );

      final result = await command.run();

      expect(result, ExitCode.software.code);
      verify(
        () => logger.err(any(that: contains('an error occurred'))),
      ).called(1);
    });

    test('prints an error if fetch current user returns null', () async {
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => codePushClient.getCurrentUser()).thenAnswer((_) async => null);

      final result = await command.run();

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
        when(() => auth.isAuthenticated).thenReturn(true);
        when(() => codePushClient.getCurrentUser())
            .thenAnswer((_) async => noSubscriptionUser);

        final result = await command.run();

        expect(result, ExitCode.software.code);
        verify(
          () => logger.err(
            any(that: contains('You do not have an active subscription')),
          ),
        ).called(1);
      },
    );

    test('exits successfully if the user opts not to cancel', () async {
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => codePushClient.getCurrentUser())
          .thenAnswer((_) async => subscriptionUser);
      when(
        () => logger.confirm(
          any(
            that: contains(
              'This will cancel your Shorebird subscription. Are you sure?',
            ),
          ),
        ),
      ).thenReturn(false);

      final result = await command.run();

      expect(result, ExitCode.success.code);
      verify(() => logger.info('Aborting.')).called(1);
    });

    test('prints an error if call to cancel subscription fails', () async {
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => codePushClient.getCurrentUser())
          .thenAnswer((_) async => subscriptionUser);
      when(
        () => logger.confirm(
          any(
            that: contains(
              'This will cancel your Shorebird subscription. Are you sure?',
            ),
          ),
        ),
      ).thenReturn(true);
      when(() => codePushClient.cancelSubscription()).thenThrow(
        Exception('an error occurred'),
      );

      final result = await command.run();

      expect(result, ExitCode.software.code);
      verify(
        () => progress.fail(
          any(that: contains('an error occurred')),
        ),
      ).called(1);
    });

    test('exits successfully on subscription cancellation', () async {
      // Fri Apr 14 2023 07:00:00 GMT+0000
      const cancellationTimestamp = 1681455600;

      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => codePushClient.getCurrentUser())
          .thenAnswer((_) async => subscriptionUser);
      when(
        () => logger.confirm(
          any(
            that: contains(
              'This will cancel your Shorebird subscription. Are you sure?',
            ),
          ),
        ),
      ).thenReturn(true);

      when(() => codePushClient.cancelSubscription()).thenAnswer(
        (_) async => DateTime.fromMillisecondsSinceEpoch(
          cancellationTimestamp * 1000,
        ),
      );

      final result = await command.run();

      expect(result, ExitCode.success.code);

      verify(
        () => progress.complete(
          any(
            that: stringContainsInOrder([
              'Your subscription has been canceled.',
              'Your access to Shorebird will continue until April 14, 2023'
            ]),
          ),
        ),
      ).called(1);
    });
  });
}

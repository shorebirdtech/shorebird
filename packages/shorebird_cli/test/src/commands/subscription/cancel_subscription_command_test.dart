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

    late CancelSubscriptionCommand command;

    setUp(() {
      auth = _MockAuth();
      codePushClient = _MockCodePushClient();
      httpClient = _MockHttpClient();
      logger = _MockLogger();

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
        () => logger.err(
          any(that: contains('an error occurred')),
        ),
      ).called(1);
    });

    test('exits successfully on subscription cancellation', () async {
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

      when(() => codePushClient.cancelSubscription())
          .thenAnswer((_) async => {});

      final result = await command.run();

      expect(result, ExitCode.success.code);
      verify(
        () => logger.info('Your subscription has been canceled.'),
      ).called(1);
    });
  });
}

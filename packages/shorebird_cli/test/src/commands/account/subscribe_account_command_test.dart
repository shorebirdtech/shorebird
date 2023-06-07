import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/account/account.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockUser extends Mock implements User {}

void main() {
  final paymentLink = Uri.parse('https://example.com/payment-link');

  late Auth auth;
  late CodePushClient codePushClient;
  late http.Client httpClient;
  late Logger logger;
  late Progress progress;
  late User user;

  late SubscribeAccountCommand subscribeAccountCommand;

  group(SubscribeAccountCommand, () {
    setUp(() {
      auth = _MockAuth();
      codePushClient = _MockCodePushClient();
      httpClient = _MockHttpClient();
      logger = _MockLogger();
      progress = _MockProgress();
      user = _MockUser();

      when(() => auth.client).thenReturn(httpClient);
      when(() => auth.isAuthenticated).thenReturn(true);

      when(() => codePushClient.createPaymentLink())
          .thenAnswer((_) async => paymentLink);
      when(() => codePushClient.getCurrentUser()).thenAnswer((_) async => user);

      when(() => logger.err(any())).thenReturn(null);
      when(() => logger.info(any())).thenReturn(null);
      when(() => logger.progress(any())).thenReturn(progress);

      when(() => user.hasActiveSubscription).thenReturn(false);

      subscribeAccountCommand = SubscribeAccountCommand(
        logger: logger,
        auth: auth,
        buildCodePushClient: ({required httpClient, hostedUri}) =>
            codePushClient,
      );
    });

    test('has a description', () {
      expect(subscribeAccountCommand.description, isNotEmpty);
    });

    test('summary has price and link to shorebird.dev', () {
      expect(
        subscribeAccountCommand.summary,
        stringContainsInOrder([r'$20', 'shorebird.dev']),
      );
    });

    test('exits with code 67 when user is not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);

      final result = await subscribeAccountCommand.run();

      expect(result, ExitCode.noUser.code);

      verify(
        () => logger.err(any(that: contains('You must be logged in to run'))),
      ).called(1);
      verifyNever(() => codePushClient.createPaymentLink());
    });

    test('exits with code 70 when getCurrentUser throws an exception',
        () async {
      when(() => codePushClient.getCurrentUser())
          .thenThrow(Exception('oh no!'));

      final result = await subscribeAccountCommand.run();

      expect(result, ExitCode.software.code);
      verify(() => progress.fail(any(that: contains('oh no!')))).called(1);
      verifyNever(() => codePushClient.createPaymentLink());
    });

    test('exits with code 70 when getCurrentUser returns null', () async {
      when(() => codePushClient.getCurrentUser()).thenAnswer((_) async => null);

      final result = await subscribeAccountCommand.run();

      expect(result, ExitCode.software.code);
      verify(
        () => progress.fail(
          any(
            that: contains(
              "We're having trouble retrieving your account information",
            ),
          ),
        ),
      ).called(1);
      verifyNever(() => codePushClient.createPaymentLink());
    });

    test(
        'exits with code 0 and prints message and exits if user already has '
        'an active subscription', () async {
      when(() => user.hasActiveSubscription).thenReturn(true);
      final result = await subscribeAccountCommand.run();

      expect(result, ExitCode.success.code);
      verify(
        () => progress.complete(
          any(that: contains('You already have an active subscription')),
        ),
      ).called(1);
      verifyNever(() => codePushClient.createPaymentLink());
    });

    test('exits with code 70 and prints error if createPaymentLink fails',
        () async {
      const errorMessage = 'failed to create payment link';
      when(() => codePushClient.createPaymentLink())
          .thenThrow(Exception(errorMessage));

      final result = await subscribeAccountCommand.run();

      expect(result, ExitCode.software.code);
      verify(() => codePushClient.createPaymentLink()).called(1);
      verify(() => progress.fail(any(that: contains(errorMessage)))).called(1);
    });

    test('exits with code 0 and prints payment link', () async {
      final result = await subscribeAccountCommand.run();

      expect(result, ExitCode.success.code);
      verify(() => progress.complete('Link generated!')).called(1);
      verify(
        () => logger.info(any(that: contains(paymentLink.toString()))),
      ).called(1);
      verify(() => codePushClient.createPaymentLink()).called(1);
    });
  });
}

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
  const userName = 'John Doe';
  const email = 'tester@shorebird.dev';
  final paymentLink = Uri.parse('https://example.com/payment-link');

  late Auth auth;
  late CodePushClient codePushClient;
  late http.Client httpClient;
  late Logger logger;
  late Progress progress;
  late User user;

  late CreateAccountCommand createAccountCommand;

  group(CreateAccountCommand, () {
    setUp(() {
      auth = _MockAuth();
      codePushClient = _MockCodePushClient();
      httpClient = _MockHttpClient();
      logger = _MockLogger();
      progress = _MockProgress();
      user = _MockUser();

      createAccountCommand = CreateAccountCommand(
        logger: logger,
        auth: auth,
        buildCodePushClient: ({required httpClient, hostedUri}) =>
            codePushClient,
      );

      when(() => auth.client).thenReturn(httpClient);
      when(() => auth.email).thenReturn(email);
      when(() => auth.credentialsFilePath).thenReturn('credentials.json');
      when(() => auth.isAuthenticated).thenReturn(false);
      when(
        () => auth.login(any(), verifyEmail: any(named: 'verifyEmail')),
      ).thenAnswer((_) async {});

      when(() => codePushClient.createUser(name: userName))
          .thenAnswer((_) async => user);
      when(() => codePushClient.createPaymentLink())
          .thenAnswer((_) async => paymentLink);
      when(() => codePushClient.getCurrentUser()).thenThrow(
        Exception('failed to get current user'),
      );

      when(() => logger.err(any())).thenReturn(null);
      when(() => logger.info(any())).thenReturn(null);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.prompt(any())).thenReturn(userName);

      when(() => progress.complete(any())).thenReturn(null);
      when(() => progress.fail(any())).thenReturn(null);

      when(() => user.displayName).thenReturn(userName);
    });

    test('has a description', () {
      expect(createAccountCommand.description, isNotEmpty);
    });

    test('login prompt is correct', () {
      createAccountCommand.prompt('https://shorebird.dev');
      verify(
        () => logger.info('''
Shorebird is currently only open to trusted testers. To participate, you will need a Google account for authentication.

The first step is to sign in with a Google account. Please follow the sign-in link below:

${styleBold.wrap(styleUnderlined.wrap(lightCyan.wrap('https://shorebird.dev')))}

Waiting for your authorization...'''),
      ).called(1);
    });

    test('exits with code 70 when login fails', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      when(
        () => auth.login(any(), verifyEmail: any(named: 'verifyEmail')),
      ).thenThrow(Exception('login failed'));

      final result = await createAccountCommand.run();

      expect(result, ExitCode.software.code);
      verify(() => auth.login(any(), verifyEmail: false)).called(1);
      verify(() => logger.err(any(that: contains('login failed')))).called(1);
    });

    test(
        'exits with code 0 and prints message and exits if user already has an '
        'account', () async {
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => codePushClient.getCurrentUser()).thenAnswer((_) async => user);

      final result = await createAccountCommand.run();

      expect(result, ExitCode.success.code);
      verify(
        () => logger.info(any(that: contains('You already have an account'))),
      ).called(1);
    });

    test(
      'proceeds with account creation if user is authenticated but does not '
      'have an account',
      () async {
        when(() => auth.isAuthenticated).thenReturn(true);
        final result = await createAccountCommand.run();

        expect(result, ExitCode.success.code);
        verify(() => codePushClient.createUser(name: userName)).called(1);
        verify(() => codePushClient.createPaymentLink()).called(1);
      },
    );

    test('exits with code 70 if createUser fails', () async {
      const errorMessage = 'failed to create user';
      when(() => auth.isAuthenticated).thenReturn(false);
      when(() => codePushClient.createUser(name: any(named: 'name')))
          .thenThrow(Exception(errorMessage));

      final result = await createAccountCommand.run();

      expect(result, ExitCode.software.code);
      verify(() => auth.login(any(), verifyEmail: false)).called(1);
      verify(() => codePushClient.createUser(name: userName)).called(1);
      verifyNever(() => codePushClient.createPaymentLink());
      verify(() => progress.fail(any(that: contains(errorMessage)))).called(1);
    });

    test('exits with code 70 if createPaymentLink fails', () async {
      const errorMessage = 'failed to create payment link';

      when(() => auth.isAuthenticated).thenReturn(false);
      when(() => codePushClient.createPaymentLink())
          .thenThrow(Exception(errorMessage));

      final result = await createAccountCommand.run();

      expect(result, ExitCode.software.code);
      verify(() => auth.login(any(), verifyEmail: false)).called(1);
      verify(() => codePushClient.createUser(name: userName)).called(1);
      verify(() => codePushClient.createPaymentLink()).called(1);
      verify(() => progress.fail(any(that: contains(errorMessage)))).called(1);
    });

    test('exits with code 0, creates account with name provided by user',
        () async {
      final result = await createAccountCommand.run();

      expect(result, ExitCode.success.code);
      verify(() => auth.login(any(), verifyEmail: false)).called(1);
      verify(() => logger.prompt('What is your name?')).called(1);
      verify(() => codePushClient.createUser(name: userName)).called(1);
      verify(() => codePushClient.createPaymentLink()).called(1);
      verify(
        () => progress.complete(
          any(
            that: stringContainsInOrder([
              'Welcome to Shorebird',
              userName,
              email,
              'purchase a Shorebird subscription',
              paymentLink.toString(),
            ]),
          ),
        ),
      ).called(1);
    });
  });
}

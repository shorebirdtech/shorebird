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
      when(() => auth.getCredentials(any())).thenAnswer((_) async {});

      when(() => codePushClient.createUser(name: userName))
          .thenAnswer((_) async => user);
      when(() => codePushClient.getCurrentUser())
          .thenThrow(UserNotFoundException());

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.prompt(any())).thenReturn(userName);

      when(() => progress.complete(any())).thenReturn(null);
      when(() => progress.fail(any())).thenReturn(null);

      when(() => user.displayName).thenReturn(userName);
      when(() => user.email).thenReturn(email);
    });

    test('has a description', () {
      expect(createAccountCommand.description, isNotEmpty);
    });

    test('login prompt is correct', () {
      createAccountCommand.prompt('https://shorebird.dev');
      verify(
        () => logger.info('''
Shorebird currently requires a Google account for authentication. If you'd like to use a different kind of auth, please let us know: ${lightCyan.wrap('https://github.com/shorebirdtech/shorebird/issues/335')}.

Follow the link below to authenticate:

${styleBold.wrap(styleUnderlined.wrap(lightCyan.wrap('https://shorebird.dev')))}

Waiting for your authorization...'''),
      ).called(1);
    });

    test('exits with code 0 if user is logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(true);

      final result = await createAccountCommand.run();

      expect(result, ExitCode.success.code);

      verify(
        () => logger.info(any(that: contains('You are already logged in '))),
      ).called(1);
    });

    test('exits with code 70 when getCredentials fails', () async {
      when(
        () => auth.getCredentials(any()),
      ).thenThrow(Exception('login failed'));

      final result = await createAccountCommand.run();

      expect(result, ExitCode.software.code);
      verify(() => auth.getCredentials(any())).called(1);
      verify(() => logger.err(any(that: contains('login failed')))).called(1);
    });

    test(
        'exits with code 0 and prints message and exits if user already has an '
        'account', () async {
      when(() => codePushClient.getCurrentUser()).thenAnswer((_) async => user);

      final result = await createAccountCommand.run();

      expect(result, ExitCode.success.code);
      verify(
        () => logger.info(any(that: contains('You already have an account'))),
      ).called(1);
    });

    test('exits with code 70 if an unknown error occurs in getCurrentUser',
        () async {
      when(() => codePushClient.getCurrentUser()).thenThrow(Exception('oh no'));

      final result = await createAccountCommand.run();

      expect(result, ExitCode.software.code);
      verify(() => logger.err(any(that: contains('oh no')))).called(1);
    });

    test('exits with code 70 if createUser fails', () async {
      const errorMessage = 'failed to create user';
      when(() => codePushClient.createUser(name: any(named: 'name')))
          .thenThrow(Exception(errorMessage));

      final result = await createAccountCommand.run();

      expect(result, ExitCode.software.code);
      verify(() => auth.getCredentials(any())).called(1);
      verify(() => auth.logout()).called(1);
      verify(() => codePushClient.createUser(name: userName)).called(1);
      verify(() => progress.fail(any(that: contains(errorMessage)))).called(1);
    });

    test('exits with code 0, creates account with name provided by user',
        () async {
      final result = await createAccountCommand.run();

      expect(result, ExitCode.success.code);
      verify(() => auth.getCredentials(any())).called(1);
      verify(
        () =>
            logger.prompt('Tell us your name to finish creating your account:'),
      ).called(1);
      verify(
        () => progress.complete(
          any(
            that: stringContainsInOrder(['Account created', email]),
          ),
        ),
      ).called(1);
      verify(() => codePushClient.createUser(name: userName)).called(1);
      verify(
        () => logger.info(
          any(
            that: stringContainsInOrder([
              'Welcome to Shorebird',
              userName,
              'shorebird account subscribe',
            ]),
          ),
        ),
      ).called(1);
    });
  });
}

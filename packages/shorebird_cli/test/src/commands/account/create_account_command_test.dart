import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/account/account.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements Auth {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockLogger extends Mock implements Logger {}

class _MockUser extends Mock implements User {}

void main() {
  group(CreateAccountCommand, () {
    const userName = 'John Doe';
    const email = 'tester@shorebird.dev';

    late Auth auth;
    late http.Client httpClient;
    late Logger logger;
    late User user;

    late CreateAccountCommand createAccountCommand;

    setUp(() {
      auth = _MockAuth();
      httpClient = _MockHttpClient();
      logger = _MockLogger();
      user = _MockUser();

      when(() => auth.client).thenReturn(httpClient);
      when(() => auth.credentialsFilePath).thenReturn('credentials.json');

      when(() => logger.prompt(any())).thenReturn(userName);

      when(() => user.displayName).thenReturn(userName);
      when(() => user.email).thenReturn(email);

      createAccountCommand = CreateAccountCommand(
        logger: logger,
        auth: auth,
      );
    });

    test('has a description', () {
      expect(createAccountCommand.description, isNotEmpty);
    });

    test('login prompt is correct', () {
      createAccountCommand.authPrompt('https://shorebird.dev');
      verify(
        () => logger.info('''
Shorebird currently requires a Google account for authentication. If you'd like to use a different kind of auth, please let us know: ${lightCyan.wrap('https://github.com/shorebirdtech/shorebird/issues/335')}.

Follow the link below to authenticate:

${styleBold.wrap(styleUnderlined.wrap(lightCyan.wrap('https://shorebird.dev')))}

Waiting for your authorization...'''),
      ).called(1);
    });

    test('namePrompt asks user for name', () {
      final name = createAccountCommand.namePrompt();
      expect(name, userName);
      verify(
        () =>
            logger.prompt('Tell us your name to finish creating your account:'),
      ).called(1);
    });

    test('exits with code 0 if user is logged in', () async {
      when(
        () => auth.signUp(
          authPrompt: any(named: 'authPrompt'),
          namePrompt: any(named: 'namePrompt'),
        ),
      ).thenThrow(UserAlreadyLoggedInException(email: email));

      final result = await createAccountCommand.run();

      expect(result, ExitCode.success.code);

      verify(
        () => logger.info(any(that: contains('You are already logged in '))),
      ).called(1);
    });

    test(
        'exits with code 0 and prints message and exits if user already has an '
        'account', () async {
      when(
        () => auth.signUp(
          authPrompt: any(named: 'authPrompt'),
          namePrompt: any(named: 'namePrompt'),
        ),
      ).thenThrow(UserAlreadyExistsException(user));

      final result = await createAccountCommand.run();

      expect(result, ExitCode.success.code);
      verify(
        () => logger.info(any(that: contains('You already have an account'))),
      ).called(1);
    });

    test('exits with code 70 when signUp fails', () async {
      when(
        () => auth.signUp(
          authPrompt: any(named: 'authPrompt'),
          namePrompt: any(named: 'namePrompt'),
        ),
      ).thenThrow(Exception('login failed'));

      final result = await createAccountCommand.run();

      expect(result, ExitCode.software.code);
      verify(() => logger.err(any(that: contains('login failed')))).called(1);
    });

    test('exits with code 0, creates account with name provided by user',
        () async {
      when(
        () => auth.signUp(
          authPrompt: any(named: 'authPrompt'),
          namePrompt: any(named: 'namePrompt'),
        ),
      ).thenAnswer((_) async => user);

      final result = await createAccountCommand.run();

      expect(result, ExitCode.success.code);
      verify(
        () => auth.signUp(
          authPrompt: any(named: 'authPrompt'),
          namePrompt: any(named: 'namePrompt'),
        ),
      ).called(1);
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

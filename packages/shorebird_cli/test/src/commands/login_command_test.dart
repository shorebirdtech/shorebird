import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/login_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

void main() {
  group('login', () {
    const email = 'test@email.com';

    late Directory applicationConfigHome;
    late Logger logger;
    late Auth auth;
    late LoginCommand loginCommand;

    setUp(() {
      applicationConfigHome = Directory.systemTemp.createTempSync();
      logger = _MockLogger();
      auth = _MockAuth();
      loginCommand = LoginCommand(auth: auth, logger: logger);

      when(() => auth.credentialsFilePath).thenReturn(
        p.join(applicationConfigHome.path, 'credentials.json'),
      );
    });

    test('exits with code 0 when already logged in', () async {
      when(() => auth.login(any()))
          .thenThrow(UserAlreadyLoggedInException(email: email));

      final result = await loginCommand.run();
      expect(result, equals(ExitCode.success.code));

      verify(
        () => logger.info('You are already logged in as <$email>.'),
      ).called(1);
      verify(
        () => logger.info(
          "Run ${lightCyan.wrap('shorebird logout')} to log out and try again.",
        ),
      ).called(1);
    });

    test('exits with code 70 if no user is found', () async {
      when(() => auth.login(any()))
          .thenThrow(UserNotFoundException(email: email));

      final result = await loginCommand.run();
      expect(result, equals(ExitCode.software.code));

      verify(
        () => logger.err('We could not find a Shorebird account for $email.'),
      ).called(1);
      verify(
        () => logger.info(any(that: contains('shorebird account create'))),
      ).called(1);
    });

    test('exits with code 70 when error occurs', () async {
      final error = Exception('oops something went wrong!');
      when(() => auth.login(any())).thenThrow(error);

      final result = await loginCommand.run();
      expect(result, equals(ExitCode.software.code));

      verify(() => auth.login(any())).called(1);
      verify(() => logger.err(error.toString())).called(1);
    });

    test('exits with code 70 if user does not have an account', () async {
      when(() => auth.login(any())).thenThrow(UserNotFoundException());

      final result = await loginCommand.run();

      expect(result, equals(ExitCode.software.code));
      verify(() => auth.login(any())).called(1);
      verify(
        () => logger.err(
          any(
            that: stringContainsInOrder([
              "We don't recognize that email address",
              'shorebird account create',
            ]),
          ),
        ),
      ).called(1);
    });

    test('exits with code 0 when logged in successfully', () async {
      when(() => auth.login(any())).thenAnswer((_) async {});
      when(() => auth.email).thenReturn(email);

      final result = await loginCommand.run();
      expect(result, equals(ExitCode.success.code));

      verify(() => auth.login(any())).called(1);
      verify(
        () => logger.info(
          any(that: contains('You are now logged in as <$email>.')),
        ),
      ).called(1);
    });

    test('prompt is correct', () {
      const url = 'http://example.com';
      loginCommand.prompt(url);

      verify(
        () => logger.info('''
The Shorebird CLI needs your authorization to manage apps, releases, and patches on your behalf.

In a browser, visit this URL to log in:

${styleBold.wrap(styleUnderlined.wrap(lightCyan.wrap(url)))}

Waiting for your authorization...'''),
      ).called(1);
    });
  });
}

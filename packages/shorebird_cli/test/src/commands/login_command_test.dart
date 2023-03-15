import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/session.dart';
import 'package:shorebird_cli/src/commands/login_command.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

void main() {
  group('login', () {
    const apiKey = 'test-api-key';
    const session = Session(apiKey: apiKey);

    late Logger logger;
    late Auth auth;
    late LoginCommand loginCommand;

    setUp(() {
      logger = _MockLogger();
      auth = _MockAuth();
      loginCommand = LoginCommand(auth: auth, logger: logger);

      when(() => logger.progress(any())).thenReturn(_MockProgress());
    });

    test('exits with code 0 when already logged in', () async {
      when(() => auth.currentSession).thenReturn(session);

      final result = await loginCommand.run();
      expect(result, equals(ExitCode.success.code));

      verify(() => logger.info('You are already logged in.')).called(1);
      verify(
        () => logger.info("Run 'shorebird logout' to log out and try again."),
      ).called(1);
    });

    test('exits with code 70 when error occurs', () async {
      final error = Exception('oops something went wrong!');
      when(() => logger.prompt(any())).thenReturn(apiKey);
      when(() => auth.currentSession).thenReturn(null);
      when(
        () => auth.login(apiKey: any(named: 'apiKey')),
      ).thenThrow(error);

      final result = await loginCommand.run();
      expect(result, equals(ExitCode.software.code));

      verify(() => logger.progress('Logging into shorebird.dev')).called(1);
      verify(() => auth.login(apiKey: apiKey)).called(1);
      verify(() => logger.err(error.toString())).called(1);
    });

    test('exits with code 0 when logged in successfully', () async {
      when(() => logger.prompt(any())).thenReturn(apiKey);
      when(() => auth.currentSession).thenReturn(null);
      when(
        () => auth.login(apiKey: any(named: 'apiKey')),
      ).thenAnswer((_) async {});

      final result = await loginCommand.run();
      expect(result, equals(ExitCode.success.code));

      verify(() => logger.progress('Logging into shorebird.dev')).called(1);
      verify(() => auth.login(apiKey: apiKey)).called(1);
      verify(
        () => logger.success('You are now logged in.'),
      ).called(1);
    });
  });
}

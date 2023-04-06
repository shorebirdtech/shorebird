import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/account_command.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

void main() {
  group('AccountCommand', () {
    const user = User(email: 'hello@shorebird.dev');

    late Auth auth;
    late Logger logger;
    late AccountCommand accountCommand;

    setUp(() {
      auth = _MockAuth();
      logger = _MockLogger();
      accountCommand = AccountCommand(logger: logger, auth: auth);

      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.user).thenReturn(user);
    });

    test("doesn't do anything if no user is logged in", () async {
      when(() => auth.isAuthenticated).thenReturn(false);

      final result = await accountCommand.run();

      expect(result, equals(ExitCode.success.code));
      verify(
        () => logger.info(any(that: contains('You are not logged in'))),
      ).called(1);
    });

    test('prints the email address of the current user', () async {
      final result = await accountCommand.run();

      expect(result, equals(ExitCode.success.code));
      verify(
        () => logger.info('You are logged in as <hello@shorebird.dev>'),
      ).called(1);
    });
  });
}

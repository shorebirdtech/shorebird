import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(LoginCiCommand, () {
    late Auth auth;
    late ShorebirdLogger logger;
    late LoginCiCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          loggerRef.overrideWith(() => logger),
        },
      );
    }

    setUp(() {
      auth = MockAuth();
      logger = MockShorebirdLogger();

      command = runWithOverrides(LoginCiCommand.new);
    });

    test('has correct name', () {
      expect(command.name, equals('login:ci'));
    });

    test('has correct description', () {
      expect(command.description, contains('deprecated'));
    });

    test('shows deprecation message and exits with code 0', () async {
      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));

      final captured = verify(
        () => logger.info(captureAny()),
      ).captured;

      final message = captured.single as String;
      expect(message, contains('shorebird login:ci is deprecated'));
      expect(message, contains('console.shorebird.dev'));
      expect(message, contains('SHOREBIRD_TOKEN'));
    });

    test('does not trigger any auth flow', () async {
      await runWithOverrides(command.run);

      verifyNoMoreInteractions(auth);
    });
  });
}

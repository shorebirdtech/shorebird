import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/session.dart';
import 'package:shorebird_cli/src/commands/logout_command.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockAuth extends Mock implements Auth {}

class _MockProgress extends Mock implements Progress {}

void main() {
  group('LogoutCommand', () {
    late Logger logger;
    late Auth auth;
    late LogoutCommand logoutCommand;

    setUp(() {
      logger = _MockLogger();
      auth = _MockAuth();
      logoutCommand = LogoutCommand(auth: auth, logger: logger);

      when(() => logger.progress(any())).thenReturn(_MockProgress());
    });

    test('exits with code 0 when already logged out', () async {
      final result = await logoutCommand.run();
      expect(result, equals(ExitCode.success.code));

      verify(
        () => logger.info('You are already logged out.'),
      ).called(1);
    });

    test('exits with code 0 when logged out successfully', () async {
      const session = Session(apiKey: 'test-api-key', projectId: 'example');
      when(() => auth.currentSession).thenReturn(session);

      final progress = _MockProgress();
      when(() => progress.complete(any())).thenAnswer((invocation) {});
      when(() => logger.progress(any())).thenReturn(progress);

      final result = await logoutCommand.run();
      expect(result, equals(ExitCode.success.code));

      verify(() => logger.progress('Logging out of shorebird.dev')).called(1);
      verify(() => auth.logout()).called(1);
    });
  });
}

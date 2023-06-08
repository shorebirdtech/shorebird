import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/logout_command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockProgress extends Mock implements Progress {}

void main() {
  group('logout', () {
    late Auth auth;
    late Logger logger;
    late http.Client httpClient;
    late LogoutCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(body, values: {loggerRef.overrideWith(() => logger)});
    }

    setUp(() {
      auth = _MockAuth();
      httpClient = _MockHttpClient();
      logger = _MockLogger();

      when(() => auth.client).thenReturn(httpClient);
      when(() => logger.progress(any())).thenReturn(_MockProgress());

      command = LogoutCommand(auth: auth);
    });

    test('exits with code 0 when already logged out', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));

      verify(
        () => logger.info('You are already logged out.'),
      ).called(1);
    });

    test('exits with code 0 when logged out successfully', () async {
      when(() => auth.isAuthenticated).thenReturn(true);

      final progress = _MockProgress();
      when(() => progress.complete(any())).thenAnswer((invocation) {});
      when(() => logger.progress(any())).thenReturn(progress);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));

      verify(() => logger.progress('Logging out of shorebird.dev')).called(1);
      verify(() => auth.logout()).called(1);
    });
  });
}

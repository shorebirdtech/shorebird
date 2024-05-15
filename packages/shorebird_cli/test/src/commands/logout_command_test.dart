import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/logout_command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(LogoutCommand, () {
    late Auth auth;
    late ShorebirdLogger logger;
    late http.Client httpClient;
    late LogoutCommand command;

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
      httpClient = MockHttpClient();
      logger = MockShorebirdLogger();

      when(() => auth.client).thenReturn(httpClient);
      when(() => logger.progress(any())).thenReturn(MockProgress());

      command = runWithOverrides(LogoutCommand.new);
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

      final progress = MockProgress();
      when(() => progress.complete(any())).thenAnswer((invocation) {});
      when(() => logger.progress(any())).thenReturn(progress);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));

      verify(() => logger.progress('Logging out of shorebird.dev')).called(1);
      verify(() => auth.logout()).called(1);
    });
  });
}

import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/login_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:test/test.dart';

class _MockAccessCredentials extends Mock implements AccessCredentials {}

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

void main() {
  group('login', () {
    final credentials = _MockAccessCredentials();

    late Directory applicationConfigHome;
    late Logger logger;
    late Auth auth;
    late LoginCommand loginCommand;

    setUp(() {
      applicationConfigHome = Directory.systemTemp.createTempSync();
      logger = _MockLogger();
      auth = _MockAuth();
      loginCommand = LoginCommand(auth: auth, logger: logger);

      testApplicationConfigHome = (_) => applicationConfigHome.path;

      when(() => auth.credentialsFilePath).thenReturn(
        p.join(applicationConfigHome.path, 'credentials.json'),
      );
    });

    test('exits with code 0 when already logged in', () async {
      when(() => auth.credentials).thenReturn(credentials);

      final result = await loginCommand.run();
      expect(result, equals(ExitCode.success.code));

      verify(() => logger.info('You are already logged in.')).called(1);
      verify(
        () => logger.info("Run 'shorebird logout' to log out and try again."),
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

    test('exits with code 0 when logged in successfully', () async {
      when(() => auth.login(any())).thenAnswer((_) async {});

      final result = await loginCommand.run();
      expect(result, equals(ExitCode.success.code));

      verify(() => auth.login(any())).called(1);
      verify(
        () => logger.info(any(that: contains('You are now logged in.'))),
      ).called(1);
    });
  });
}

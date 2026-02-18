import 'package:http/http.dart' as http;
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
    const email = 'test@email.com';
    const apiKey = 'sb_api_test_key_123';

    late Auth auth;
    late http.Client httpClient;
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
      httpClient = MockHttpClient();
      logger = MockShorebirdLogger();

      when(() => auth.client).thenReturn(httpClient);
      when(() => auth.isAuthenticated).thenReturn(false);
      when(
        () => auth.login(prompt: any(named: 'prompt')),
      ).thenAnswer((_) async {});
      when(
        () => auth.createApiKey(name: any(named: 'name')),
      ).thenAnswer((_) async => apiKey);

      command = runWithOverrides(LoginCiCommand.new);
    });

    test('calls login when not authenticated', () async {
      await runWithOverrides(command.run);

      verify(() => auth.login(prompt: any(named: 'prompt'))).called(1);
      verify(
        () => auth.createApiKey(name: 'SHOREBIRD_TOKEN (CLI)'),
      ).called(1);
    });

    test('skips login when already authenticated', () async {
      when(() => auth.isAuthenticated).thenReturn(true);

      await runWithOverrides(command.run);

      verifyNever(() => auth.login(prompt: any(named: 'prompt')));
      verify(
        () => auth.createApiKey(name: 'SHOREBIRD_TOKEN (CLI)'),
      ).called(1);
    });

    test('exits with code 70 if no user is found', () async {
      when(
        () => auth.login(prompt: any(named: 'prompt')),
      ).thenThrow(UserNotFoundException(email: email));

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.software.code));

      verify(
        () => logger.err(
          'We could not find a Shorebird account for $email.',
        ),
      ).called(1);
      verify(
        () => logger.info(
          any(that: contains('https://console.shorebird.dev')),
        ),
      ).called(1);
    });

    test('exits with code 70 when error occurs', () async {
      final error = Exception('oops something went wrong!');
      when(
        () => auth.createApiKey(name: any(named: 'name')),
      ).thenThrow(error);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.software.code));

      verify(() => logger.err(error.toString())).called(1);
    });

    test('exits with code 0 when logged in successfully', () async {
      when(() => auth.email).thenReturn(email);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));

      verify(
        () => logger.info(
          any(that: contains('${lightCyan.wrap(apiKey)}')),
        ),
      ).called(1);
    });

    test('prompt is correct', () {
      const url = 'http://example.com';
      runWithOverrides(() => command.prompt(url));

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

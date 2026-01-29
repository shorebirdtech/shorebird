import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(LoginCiCommand, () {
    const email = 'test@email.com';

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
      when(
        () => auth.loginCI(prompt: any(named: 'prompt')),
      ).thenAnswer(
        (_) async => const CiToken(
          refreshToken: 'sb_rt_test_token',
          authProvider: AuthProvider.shorebird,
        ),
      );

      command = runWithOverrides(LoginCiCommand.new);
    });

    test('exits with code 70 if no user is found', () async {
      when(
        () => auth.loginCI(prompt: any(named: 'prompt')),
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
        () => auth.loginCI(prompt: any(named: 'prompt')),
      ).thenThrow(error);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.software.code));

      verify(
        () => auth.loginCI(prompt: any(named: 'prompt')),
      ).called(1);
      verify(() => logger.err(error.toString())).called(1);
    });

    test('exits with code 0 when logged in successfully', () async {
      const token = CiToken(
        refreshToken: 'sb_rt_test_token',
        authProvider: AuthProvider.shorebird,
      );
      when(
        () => auth.loginCI(prompt: any(named: 'prompt')),
      ).thenAnswer((_) async => token);
      when(() => auth.email).thenReturn(email);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));

      verify(
        () => auth.loginCI(prompt: any(named: 'prompt')),
      ).called(1);
      verify(
        () => logger.info(
          any(
            that: contains('${lightCyan.wrap(token.toBase64())}'),
          ),
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

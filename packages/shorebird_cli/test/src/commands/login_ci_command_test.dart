import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(LoginCiCommand, () {
    const email = 'test@email.com';

    late ArgResults results;
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

    setUpAll(() {
      registerFallbackValue(AuthProvider.google);
    });

    setUp(() {
      auth = MockAuth();
      httpClient = MockHttpClient();
      logger = MockShorebirdLogger();
      results = MockArgResults();

      when(() => results.wasParsed('provider')).thenReturn(false);
      when(() => results['provider']).thenReturn(null);
      when(() => auth.client).thenReturn(httpClient);
      when(
        () => logger.chooseOne<AuthProvider>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).thenReturn(AuthProvider.google);

      command =
          runWithOverrides(() => LoginCiCommand()..testArgResults = results);
    });

    group('provider', () {
      group('when provider is passed as an arg', () {
        const provider = AuthProvider.google;

        setUp(() {
          when(() => results.wasParsed('provider')).thenReturn(true);
          when(() => results['provider']).thenReturn(provider.name);
        });

        test('uses the passed provider', () async {
          await runWithOverrides(() => command.run());

          verify(
            () => auth.loginCI(
              provider,
              prompt: any(named: 'prompt'),
            ),
          ).called(1);
        });
      });

      group('when provider is not passed as an arg', () {
        const provider = AuthProvider.microsoft;

        setUp(() {
          when(() => results.wasParsed('provider')).thenReturn(false);
          when(
            () => logger.chooseOne<AuthProvider>(
              any(),
              choices: any(named: 'choices'),
              display: captureAny(named: 'display'),
            ),
          ).thenReturn(provider);
        });

        test('uses the provider chosen by the user', () async {
          await runWithOverrides(() => command.run());

          verify(
            () => auth.loginCI(
              provider,
              prompt: any(named: 'prompt'),
            ),
          ).called(1);
          final captured = verify(
            () => logger.chooseOne<AuthProvider>(
              any(),
              choices: any(named: 'choices'),
              display: captureAny(named: 'display'),
            ),
          ).captured.single as String Function(AuthProvider);
          expect(captured(AuthProvider.google), contains('Google'));
        });
      });
    });

    test('exits with code 70 if no user is found', () async {
      when(
        () => auth.loginCI(
          any(),
          prompt: any(named: 'prompt'),
        ),
      ).thenThrow(UserNotFoundException(email: email));

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.software.code));

      verify(
        () => logger.err('We could not find a Shorebird account for $email.'),
      ).called(1);
      verify(
        () => logger.info(any(that: contains('https://console.shorebird.dev'))),
      ).called(1);
    });

    test('exits with code 70 when error occurs', () async {
      final error = Exception('oops something went wrong!');
      when(
        () => auth.loginCI(
          any(),
          prompt: any(named: 'prompt'),
        ),
      ).thenThrow(error);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.software.code));

      verify(
        () => auth.loginCI(
          any(),
          prompt: any(named: 'prompt'),
        ),
      ).called(1);
      verify(() => logger.err(error.toString())).called(1);
    });

    test('exits with code 0 when logged in successfully', () async {
      const token = CiToken(
        // "shorebird-token" in base64
        refreshToken: 'c2hvcmViaXJkLXRva2Vu',
        authProvider: AuthProvider.google,
      );
      when(
        () => auth.loginCI(
          any(),
          prompt: any(named: 'prompt'),
        ),
      ).thenAnswer((_) async => token);
      when(() => auth.email).thenReturn(email);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));

      verify(
        () => auth.loginCI(
          any(),
          prompt: any(named: 'prompt'),
        ),
      ).called(1);
      verify(
        () => logger.info(
          any(that: contains('${lightCyan.wrap(token.toBase64())}')),
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

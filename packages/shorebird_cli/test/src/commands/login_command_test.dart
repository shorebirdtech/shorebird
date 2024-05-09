import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/login_command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(LoginCommand, () {
    const email = 'test@email.com';

    late ArgResults results;
    late Auth auth;
    late http.Client httpClient;
    late Directory applicationConfigHome;
    late ShorebirdLogger logger;
    late LoginCommand command;

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
      applicationConfigHome = Directory.systemTemp.createTempSync();
      results = MockArgResults();
      auth = MockAuth();
      httpClient = MockHttpClient();
      logger = MockShorebirdLogger();

      when(() => results.wasParsed('provider')).thenReturn(false);
      when(() => results['provider']).thenReturn(null);
      when(() => auth.isAuthenticated).thenReturn(false);
      when(() => auth.client).thenReturn(httpClient);
      when(() => auth.credentialsFilePath).thenReturn(
        p.join(applicationConfigHome.path, 'credentials.json'),
      );
      when(
        () => logger.chooseOne<AuthProvider>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).thenReturn(AuthProvider.google);

      command =
          runWithOverrides(() => LoginCommand()..testArgResults = results);
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
            () => auth.login(
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
              display: any(named: 'display'),
            ),
          ).thenReturn(provider);
        });

        test('uses the provider chosen by the user', () async {
          await runWithOverrides(() => command.run());

          verify(
            () => auth.login(
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

    group('when user is already logged in', () {
      setUp(() {
        when(() => auth.isAuthenticated).thenReturn(true);
        when(() => auth.email).thenReturn(email);
      });

      test('prints message and exits with code 0 when already logged in',
          () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info('You are already logged in as <$email>.'),
        ).called(1);
        verify(
          () => logger.info(
            '''Run ${lightCyan.wrap('shorebird logout')} to log out and try again.''',
          ),
        ).called(1);
        verifyNever(() => auth.login(any(), prompt: any(named: 'prompt')));
      });
    });

    test('exits with code 70 if no user is found', () async {
      when(
        () => auth.login(
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
        () => logger.info(any(that: contains('console.shorebird.dev'))),
      ).called(1);
    });

    test('exits with code 70 when error occurs', () async {
      final error = Exception('oops something went wrong!');
      when(
        () => auth.login(
          any(),
          prompt: any(named: 'prompt'),
        ),
      ).thenThrow(error);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.software.code));

      verify(
        () => auth.login(
          any(),
          prompt: any(named: 'prompt'),
        ),
      ).called(1);
      verify(() => logger.err(error.toString())).called(1);
    });

    test('exits with code 0 when logged in successfully', () async {
      when(
        () => auth.login(
          any(),
          prompt: any(named: 'prompt'),
        ),
      ).thenAnswer((_) async {});
      when(() => auth.email).thenReturn(email);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));

      verify(
        () => auth.login(
          any(),
          prompt: any(named: 'prompt'),
        ),
      ).called(1);
      verify(
        () => logger.info(
          any(that: contains('You are now logged in as <$email>.')),
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

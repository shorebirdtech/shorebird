import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/login_command.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(LoginCommand, () {
    const email = 'test@email.com';

    late Auth auth;
    late http.Client httpClient;
    late Directory applicationConfigHome;
    late ShorebirdLogger logger;
    late Progress progress;
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

    setUp(() {
      applicationConfigHome = Directory.systemTemp.createTempSync();
      auth = MockAuth();
      httpClient = MockHttpClient();
      logger = MockShorebirdLogger();
      progress = MockProgress();

      when(() => auth.isAuthenticated).thenReturn(false);
      when(() => auth.hasValidCredentials()).thenAnswer((_) async => true);
      when(() => auth.clearCredentials()).thenReturn(null);
      when(() => auth.client).thenReturn(httpClient);
      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => auth.credentialsFilePath,
      ).thenReturn(p.join(applicationConfigHome.path, 'credentials.json'));
      when(
        () => auth.login(prompt: any(named: 'prompt')),
      ).thenAnswer((_) async {});

      command = runWithOverrides(LoginCommand.new);
    });

    test('has correct name', () {
      expect(command.name, 'login');
    });

    test('has correct description', () {
      expect(command.description, 'Login as a new Shorebird user.');
    });

    group('when user is already logged in', () {
      setUp(() {
        when(() => auth.isAuthenticated).thenReturn(true);
        when(() => auth.email).thenReturn(email);
      });

      test(
        'prints message and exits with code 0 when already logged in',
        () async {
          final result = await runWithOverrides(command.run);

          expect(result, equals(ExitCode.success.code));
          verify(
            () => logger.info('You are already logged in as <$email>.'),
          ).called(1);
          verify(
            () => logger.info(
              '''Run ${lightCyan.wrap('shorebird logout')} to log in as a different user.''',
            ),
          ).called(1);
          verifyNever(() => auth.login(prompt: any(named: 'prompt')));
        },
      );
    });

    group('when user is authenticated via API key', () {
      setUp(() {
        when(() => auth.isAuthenticated).thenReturn(true);
        when(() => auth.email).thenReturn(null);
      });

      test('points at the environment variable and exits with code 0', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info(
            '''You are already authenticated via the $shorebirdTokenEnvVar environment variable.''',
          ),
        ).called(1);
        verify(
          () => logger.info(
            '''Unset $shorebirdTokenEnvVar to log in as a different user.''',
          ),
        ).called(1);
        verifyNever(() => auth.login(prompt: any(named: 'prompt')));
      });
    });

    group('when stored credentials have expired', () {
      setUp(() {
        when(() => auth.isAuthenticated).thenReturn(true);
        when(() => auth.email).thenReturn(email);
        when(() => auth.hasValidCredentials()).thenAnswer((_) async => false);
      });

      test('clears credentials and logs in again', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(() => progress.fail('Your credentials have expired.')).called(1);
        verify(() => logger.info('Logging you in again...')).called(1);
        verify(() => auth.clearCredentials()).called(1);
        verify(() => auth.login(prompt: any(named: 'prompt'))).called(1);
        verifyNever(
          () => logger.info('You are already logged in as <$email>.'),
        );
        verifyNever(() => progress.complete(any()));
      });
    });

    // Treating an unreachable auth service as a rejection would log a user
    // out for running `shorebird login` off wifi.
    group('when the credential check cannot reach the auth service', () {
      setUp(() {
        when(() => auth.isAuthenticated).thenReturn(true);
        when(() => auth.email).thenReturn(email);
        when(
          () => auth.hasValidCredentials(),
        ).thenThrow(const SocketException('no route to host'));
      });

      test('keeps the credentials and asks the user to retry', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.tempFail.code));
        verify(
          () => progress.fail('Could not reach the Shorebird auth service.'),
        ).called(1);
        verify(
          () => logger.info('Check your network connection and try again.'),
        ).called(1);
        verifyNever(() => auth.clearCredentials());
        verifyNever(() => auth.login(prompt: any(named: 'prompt')));
      });
    });

    test('exits with code 70 if no user is found', () async {
      when(
        () => auth.login(prompt: any(named: 'prompt')),
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
        () => auth.login(prompt: any(named: 'prompt')),
      ).thenThrow(error);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.software.code));

      verify(() => auth.login(prompt: any(named: 'prompt'))).called(1);
      verify(() => logger.err(error.toString())).called(1);
    });

    test('exits with code 0 when logged in successfully', () async {
      when(
        () => auth.login(prompt: any(named: 'prompt')),
      ).thenAnswer((_) async {});
      when(() => auth.email).thenReturn(email);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));

      verify(() => auth.login(prompt: any(named: 'prompt'))).called(1);
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

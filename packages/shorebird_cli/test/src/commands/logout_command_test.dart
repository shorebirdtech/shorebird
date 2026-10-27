import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/browser.dart';
import 'package:shorebird_cli/src/commands/logout_command.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(LogoutCommand, () {
    late ArgResults argResults;
    late Auth auth;
    late Browser browser;
    late ShorebirdLogger logger;
    late http.Client httpClient;
    late LogoutCommand command;
    late ShorebirdEnv shorebirdEnv;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          browserRef.overrideWith(() => browser),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUpAll(() => registerFallbackValue(Uri()));

    setUp(() {
      argResults = MockArgResults();
      auth = MockAuth();
      browser = MockBrowser();
      when(() => argResults['all']).thenReturn(false);
      when(() => browser.canOpen).thenReturn(true);
      when(() => browser.open(any())).thenAnswer((_) async => true);
      httpClient = MockHttpClient();
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();

      when(() => auth.client).thenReturn(httpClient);
      when(() => logger.progress(any())).thenReturn(MockProgress());

      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
      when(
        () => shorebirdEnv.hostedEnvironment,
      ).thenReturn(productionEnvironment);

      command = runWithOverrides(LogoutCommand.new)
        ..testArgResults = argResults;
    });

    test('exits with code 0 when already logged out', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));

      verify(() => logger.info('You are already logged out.')).called(1);
    });

    test('exits with code 0 when logged out successfully', () async {
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.logout()).thenAnswer((_) async => true);

      final progress = MockProgress();
      when(() => progress.complete(any())).thenAnswer((invocation) {});
      when(() => logger.progress(any())).thenReturn(progress);

      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));

      verify(() => logger.progress('Logging out of shorebird.dev')).called(1);
      verify(() => auth.logout()).called(1);
      verifyNever(() => logger.warn(any()));
    });

    test(
      'tells the user where to sign the session out when the server did not '
      'confirm it',
      () async {
        when(() => auth.isAuthenticated).thenReturn(true);
        when(() => auth.logout()).thenAnswer((_) async => false);

        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));

        verify(
          () => logger.warn(
            any(
              that: allOf(
                contains('Unable to confirm with the auth server'),
                contains('https://console.shorebird.dev/account'),
              ),
            ),
          ),
        ).called(1);
      },
    );

    group('with --all', () {
      final accountUrl = Uri.parse('https://console.shorebird.dev/account');

      setUp(() {
        when(() => argResults['all']).thenReturn(true);
        when(() => auth.isAuthenticated).thenReturn(true);
        when(() => auth.logout()).thenAnswer((_) async => true);
      });

      test('logs out here, then opens the sessions page', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verifyInOrder([
          () => auth.logout(),
          () => browser.open(accountUrl),
        ]);
      });

      test('still opens the sessions page when already logged out', () async {
        when(() => auth.isAuthenticated).thenReturn(false);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(() => browser.open(accountUrl)).called(1);
      });

      test('fails with the URL when not interactive', () async {
        when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.unavailable.code));
        verify(() => auth.logout()).called(1);
        verifyNever(() => browser.open(any()));
        verify(
          () => logger.err(any(that: contains('$accountUrl'))),
        ).called(1);
      });
    });
  });
}

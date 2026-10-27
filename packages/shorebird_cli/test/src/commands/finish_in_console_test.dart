import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/browser.dart';
import 'package:shorebird_cli/src/commands/finish_in_console.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

final _url = Uri.parse('https://console.shorebird.dev/account');

class _TestCommand extends ShorebirdCommand with FinishInConsole {
  @override
  String get name => 'test';

  @override
  String get description => 'A command for testing FinishInConsole.';

  @override
  Future<int> run() async =>
      finishInConsole(action: 'delete your account', url: _url);
}

void main() {
  useTempWorkingDirectory();
  group(FinishInConsole, () {
    late Browser browser;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdLogger logger;
    late _TestCommand command;

    R runWithOverrides<R>(R Function() body, {bool jsonMode = false}) {
      return runScoped(
        body,
        values: {
          browserRef.overrideWith(() => browser),
          isJsonModeRef.overrideWith(() => jsonMode),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      browser = MockBrowser();
      shorebirdEnv = MockShorebirdEnv();
      logger = MockShorebirdLogger();
      when(() => browser.canOpen).thenReturn(true);
      when(() => browser.open(any())).thenAnswer((_) async => true);
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
      command = _TestCommand();
    });

    setUpAll(() => registerFallbackValue(Uri()));

    group('in a terminal', () {
      test('opens the console page and succeeds', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(() => browser.open(_url)).called(1);
        verify(
          () => logger.info(
            any(
              that: allOf(
                startsWith(
                  'Opening the Shorebird console to delete your account:',
                ),
                contains('$_url'),
              ),
            ),
          ),
        ).called(1);
      });

      test(
        'prints the URL without opening it when there is no browser',
        () async {
          when(() => browser.canOpen).thenReturn(false);
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verifyNever(() => browser.open(any()));
          verify(
            () => logger.info(
              any(
                that: allOf(
                  startsWith(
                    'Visit the Shorebird console to delete your account:',
                  ),
                  contains('$_url'),
                ),
              ),
            ),
          ).called(1);
        },
      );
    });

    group('when not running interactively', () {
      setUp(() {
        when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);
      });

      test('fails with the console URL and opens nothing', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.unavailable.code));
        verifyNever(() => browser.open(any()));
        verify(
          () => logger.err(
            'The Shorebird CLI does not delete your account; you do it in '
            'the Shorebird console.',
          ),
        ).called(1);
        verify(
          () => logger.info('Open $_url in a browser to delete your account.'),
        ).called(1);
      });

      test('emits a console_required envelope under --json', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.unavailable.code));
        verifyNever(() => browser.open(any()));
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], JsonErrorCode.consoleRequired.code);
        expect(error['code'], 'console_required');
        expect(
          error['hint'],
          'Open $_url in a browser to delete your account.',
        );
      });
    });
  });
}

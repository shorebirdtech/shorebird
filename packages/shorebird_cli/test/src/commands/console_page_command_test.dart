import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/browser.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/console_page_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(ConsolePageCommand, () {
    final url = Uri.parse('https://console.shorebird.dev/account');

    late Browser browser;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdLogger logger;
    late ConsolePageCommand command;

    R runWithOverrides<R>(R Function() body, {bool jsonMode = false}) {
      return runScoped(
        body,
        values: {
          browserRef.overrideWith(() => browser),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => jsonMode),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUpAll(() => registerFallbackValue(Uri()));

    setUp(() {
      browser = MockBrowser();
      codePushClientWrapper = MockCodePushClientWrapper();
      shorebirdEnv = MockShorebirdEnv();
      logger = MockShorebirdLogger();
      when(() => browser.canOpen).thenReturn(true);
      when(() => browser.open(any())).thenAnswer((_) async => true);
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
      when(
        () => shorebirdEnv.hostedEnvironment,
      ).thenReturn(productionEnvironment);
      command = ConsolePageCommand(
        name: 'delete',
        action: 'delete your account',
        path: 'account',
        why: 'It cannot be undone.',
      );
    });

    test('describes what it opens and why', () {
      expect(command.name, 'delete');
      expect(
        command.description,
        allOf(
          startsWith('Opens the Shorebird console to delete your account.'),
          contains('It cannot be undone.'),
        ),
      );
    });

    test('opens the page and sends no API request', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(() => browser.open(url)).called(1);
      verifyZeroInteractions(codePushClientWrapper);
    });

    test('fails with the URL under --json and sends no request', () async {
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);
      final (:exitCode, :json) = await captureJson(
        () => runWithOverrides(command.run, jsonMode: true),
      );
      expect(exitCode, equals(ExitCode.unavailable.code));
      final error = json['error'] as Map<String, dynamic>;
      expect(error['code'], 'console_required');
      expect(error['hint'], contains('$url'));
      verifyNever(() => browser.open(any()));
      verifyZeroInteractions(codePushClientWrapper);
    });
  });
}

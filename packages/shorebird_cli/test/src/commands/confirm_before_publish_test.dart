import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/confirm_before_publish.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../matchers.dart';
import '../mocks.dart';

class _TestCommand extends ShorebirdCommand with ConfirmBeforePublish {
  _TestCommand() {
    addConfirmBeforePublishFlag();
  }

  @override
  String get name => 'test';

  @override
  String get description => 'A command for testing ConfirmBeforePublish.';
}

void main() {
  useTempWorkingDirectory();
  group(ConfirmBeforePublish, () {
    late ShorebirdLogger logger;
    late ShorebirdEnv shorebirdEnv;
    late _TestCommand command;

    R runWithOverrides<R>(R Function() body) => runScoped(
      body,
      values: {
        loggerRef.overrideWith(() => logger),
        shorebirdEnvRef.overrideWith(() => shorebirdEnv),
      },
    );

    void parse(List<String> args) {
      command.testArgResults = command.argParser.parse(args);
    }

    setUp(() {
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();
      command = _TestCommand();
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
    });

    test('adds --confirm as a hidden flag', () {
      final option = command.argParser.options[confirmArgName]!;
      expect(option.isFlag, isTrue);
      expect(option.hide, isTrue);
    });

    group('without --confirm', () {
      setUp(() => parse([]));

      test('neither fails nor prompts when the CLI cannot prompt', () {
        when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);
        runWithOverrides(command.assertCanConfirmBeforePublish);
        runWithOverrides(command.confirmBeforePublish);
        verifyNever(
          () => logger.confirm(
            any(),
            defaultValue: any(named: 'defaultValue'),
          ),
        );
      });
    });

    group('with --confirm', () {
      setUp(() => parse(['--confirm']));

      test('fails when the CLI cannot prompt', () {
        when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);
        expect(
          () => runWithOverrides(command.assertCanConfirmBeforePublish),
          throwsA(
            isA<InteractivePromptRequiredException>()
                .having(
                  (e) => e.promptText,
                  'promptText',
                  confirmBeforePublishPrompt,
                )
                .having((e) => e.hint, 'hint', confirmBeforePublishHint),
          ),
        );
      });

      test('does not fail when the CLI can prompt', () {
        runWithOverrides(command.assertCanConfirmBeforePublish);
      });

      test('continues when the user confirms', () {
        when(
          () => logger.confirm(any(), defaultValue: any(named: 'defaultValue')),
        ).thenReturn(true);
        runWithOverrides(command.confirmBeforePublish);
        verify(
          () => logger.confirm(confirmBeforePublishPrompt, defaultValue: true),
        ).called(1);
        verifyNever(() => logger.err(any()));
      });

      test('aborts with PromptDeclinedExit when the user declines', () {
        when(
          () => logger.confirm(any(), defaultValue: any(named: 'defaultValue')),
        ).thenReturn(false);
        expect(
          () => runWithOverrides(command.confirmBeforePublish),
          exitsDeclined,
        );
        verify(() => logger.err('Aborting.')).called(1);
      });
    });
  });
}

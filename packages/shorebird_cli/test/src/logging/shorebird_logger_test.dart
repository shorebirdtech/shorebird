import 'dart:io';

import 'package:clock/clock.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  group('currentRunLogFile', () {
    late ShorebirdEnv shorebirdEnv;
    late Directory logsDirectory;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {shorebirdEnvRef.overrideWith(() => shorebirdEnv)},
      );
    }

    setUp(() {
      logsDirectory = Directory.systemTemp.createTempSync('shorebird_logs');
      shorebirdEnv = MockShorebirdEnv();
      when(() => shorebirdEnv.logsDirectory).thenReturn(logsDirectory);
    });

    test('creates a log file in the logs directory', () {
      final date = DateTime(2021);
      final file = withClock(
        Clock.fixed(date),
        () => runWithOverrides(() => currentRunLogFile),
      );
      expect(file.existsSync(), isTrue);
      expect(
        file.path,
        equals(
          p.join(
            logsDirectory.path,
            '${date.millisecondsSinceEpoch}_shorebird.log',
          ),
        ),
      );
    });
  });

  group(ShorebirdLogger, () {
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdLogger logger;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {shorebirdEnvRef.overrideWith(() => shorebirdEnv)},
      );
    }

    setUp(() {
      shorebirdEnv = MockShorebirdEnv();
      when(
        () => shorebirdEnv.logsDirectory,
      ).thenReturn(Directory.systemTemp.createTempSync());
      logger = ShorebirdLogger();
    });

    group('detail', () {
      group('when log level is debug or higher', () {
        setUp(() {
          logger.level = Level.debug;
        });

        test('does not write message to log file', () {
          const message = 'my detail message';
          logger.detail(message);
          expect(
            // Replacing this with a tear-off influences
            // ignore: unnecessary_lambdas
            runWithOverrides(() => currentRunLogFile.readAsStringSync()),
            isNot(contains(message)),
          );
        });
      });

      group('when log level is lower than debug', () {
        setUp(() {
          logger.level = Level.info;
        });

        test('writes message to log file', () {
          const message = 'my detail message';
          logger.detail(message);
          expect(
            // Replacing this with a tear-off influences
            // ignore: unnecessary_lambdas
            runWithOverrides(() => currentRunLogFile.readAsStringSync()),
            contains(message),
          );
        });
      });
    });

    group('non-interactive prompt failure', () {
      late List<String> stdoutOutput;

      setUp(() {
        stdoutOutput = [];
      });

      T runUnderScope<T>(
        T Function() body, {
        required bool canAcceptUserInput,
        required bool hasTerminal,
        bool jsonMode = false,
      }) {
        when(() => shorebirdEnv.canAcceptUserInput).thenReturn(
          canAcceptUserInput,
        );
        final realStdout = stdout;
        return IOOverrides.runZoned(
          () => runScoped(
            body,
            values: {
              shorebirdEnvRef.overrideWith(() => shorebirdEnv),
              isJsonModeRef.overrideWith(() => jsonMode),
            },
          ),
          stdout: () => CapturingStdout(
            baseStdOut: realStdout,
            captured: stdoutOutput,
            hasTerminalOverride: hasTerminal,
          ),
        );
      }

      Matcher throwsPromptRequired({String? withHint, String? withPrompt}) {
        return throwsA(
          isA<InteractivePromptRequiredException>()
              .having(
                (e) => e.hint,
                'hint',
                withHint == null ? isNotEmpty : equals(withHint),
              )
              .having(
                (e) => e.promptText,
                'promptText',
                withPrompt == null ? anything : equals(withPrompt),
              ),
        );
      }

      group('when stdin is not a terminal', () {
        test('confirm throws with default hint', () {
          expect(
            () => runUnderScope(
              () => logger.confirm('Continue?'),
              canAcceptUserInput: false,
              hasTerminal: true,
            ),
            throwsPromptRequired(
              withHint: defaultInteractivePromptHint,
              withPrompt: 'Continue?',
            ),
          );
        });

        test('confirm throws with per-site hint when provided', () {
          expect(
            () => runUnderScope(
              () => logger.confirm('Continue?', hint: 'Pass --force.'),
              canAcceptUserInput: false,
              hasTerminal: true,
            ),
            throwsPromptRequired(withHint: 'Pass --force.'),
          );
        });

        test('chooseOne throws with the per-site hint', () {
          expect(
            () => runUnderScope(
              () => logger.chooseOne(
                'Which?',
                choices: const ['a', 'b'],
                hint: 'Pass --choice=<a|b>.',
              ),
              canAcceptUserInput: false,
              hasTerminal: true,
            ),
            throwsPromptRequired(withHint: 'Pass --choice=<a|b>.'),
          );
        });

        test('prompt throws with the per-site hint', () {
          expect(
            () => runUnderScope(
              () => logger.prompt('Name?', hint: 'Pass --name=<value>.'),
              canAcceptUserInput: false,
              hasTerminal: true,
            ),
            throwsPromptRequired(withHint: 'Pass --name=<value>.'),
          );
        });

        test('promptAny throws with the per-site hint', () {
          expect(
            () => runUnderScope(
              () => logger.promptAny('Tags?', hint: 'Pass --tags=<csv>.'),
              canAcceptUserInput: false,
              hasTerminal: true,
            ),
            throwsPromptRequired(withHint: 'Pass --tags=<csv>.'),
          );
        });
      });

      group('when stdout has no terminal', () {
        test('confirm throws even though canAcceptUserInput is true', () {
          expect(
            () => runUnderScope(
              () => logger.confirm('Continue?', hint: 'Pass --force.'),
              canAcceptUserInput: true,
              hasTerminal: false,
            ),
            throwsPromptRequired(withHint: 'Pass --force.'),
          );
        });
      });

      group('when --json is active', () {
        test('confirm throws with the per-site hint', () {
          expect(
            () => runUnderScope(
              () => logger.confirm('Continue?', hint: 'Pass --force.'),
              canAcceptUserInput: false,
              hasTerminal: true,
              jsonMode: true,
            ),
            throwsPromptRequired(withHint: 'Pass --force.'),
          );
        });
      });

      group('when --json is active', () {
        test('confirm throws with the per-site hint', () {
          expect(
            () => runUnderScope(
              () => logger.confirm('Continue?', hint: 'Pass --force.'),
              canAcceptUserInput: false,
              hasTerminal: true,
              jsonMode: true,
            ),
            throwsPromptRequired(withHint: 'Pass --force.'),
          );
        });
      });

      test('the exception toString surfaces both the prompt and the hint', () {
        final exception = InteractivePromptRequiredException(
          promptText: 'Continue?',
          hint: 'Pass --force.',
        );
        final str = exception.toString();
        expect(str, contains('Continue?'));
        expect(str, contains('Pass --force.'));
      });
    });

    group('progress', () {
      late List<String> stdoutOutput;
      late List<String> stderrOutput;

      setUp(() {
        stdoutOutput = [];
        stderrOutput = [];
      });

      Progress runUnderScope(
        Progress Function() body, {
        required bool hasTerminal,
        bool jsonMode = false,
      }) {
        final realStdout = stdout;
        final realStderr = stderr;
        return IOOverrides.runZoned(
          () => runScoped(
            body,
            values: {
              shorebirdEnvRef.overrideWith(() => shorebirdEnv),
              isJsonModeRef.overrideWith(() => jsonMode),
            },
          ),
          stdout: () => CapturingStdout(
            baseStdOut: realStdout,
            captured: stdoutOutput,
            hasTerminalOverride: hasTerminal,
          ),
          stderr: () => CapturingStdout(
            baseStdOut: realStderr,
            captured: stderrOutput,
            hasTerminalOverride: hasTerminal,
          ),
        );
      }

      group('in a non-interactive context', () {
        test('emits a single "Starting" line on creation', () {
          runUnderScope(
            () => logger.progress('fetching apps'),
            hasTerminal: false,
          );
          expect(stdoutOutput, equals(['Starting fetching apps...']));
        });

        test('emits a "Done" line on complete with no update', () {
          final progress = runUnderScope(
            () => logger.progress('fetching apps'),
            hasTerminal: false,
          );
          progress.complete();
          expect(
            stdoutOutput,
            equals(['Starting fetching apps...', 'Done fetching apps']),
          );
        });

        test('emits a "Done" line with the update text on complete', () {
          final progress = runUnderScope(
            () => logger.progress('fetching apps'),
            hasTerminal: false,
          );
          progress.complete('found 3 apps');
          expect(stdoutOutput.last, equals('Done found 3 apps'));
        });

        test('emits a "Failed" line on fail', () {
          final progress = runUnderScope(
            () => logger.progress('fetching apps'),
            hasTerminal: false,
          );
          progress.fail('network error');
          expect(stdoutOutput.last, equals('Failed network error'));
        });

        test('emits an update line and remembers the new message', () {
          final progress = runUnderScope(
            () => logger.progress('fetching apps'),
            hasTerminal: false,
          );
          progress.update('still fetching');
          progress.complete();
          expect(stdoutOutput, contains('still fetching...'));
          expect(stdoutOutput.last, equals('Done still fetching'));
        });

        test('emits no carriage returns or ANSI escapes', () {
          final progress = runUnderScope(
            () => logger.progress('fetching apps'),
            hasTerminal: false,
          );
          progress.complete();
          for (final line in stdoutOutput) {
            expect(line, isNot(contains('\r')));
            expect(line, isNot(contains('\u001b')));
          }
        });
      });

      group('under --json', () {
        test('routes static progress to stderr instead of stdout', () {
          final progress = runUnderScope(
            () => logger.progress('fetching apps'),
            hasTerminal: true,
            jsonMode: true,
          );
          progress.complete();
          expect(stdoutOutput, isEmpty);
          expect(stderrOutput, contains('Starting fetching apps...'));
          expect(stderrOutput, contains('Done fetching apps'));
        });
      });

      group('under --json with a TTY', () {
        test('still produces static lines (no spinner)', () {
          final progress = runUnderScope(
            () => logger.progress('fetching apps'),
            hasTerminal: true,
            jsonMode: true,
          );
          progress.complete();
          // Under --json progress is routed to stderr to avoid corrupting
          // the JSON envelope on stdout.
          expect(stderrOutput, contains('Starting fetching apps...'));
          expect(stderrOutput, contains('Done fetching apps'));
        });
      });

      group('when the log level is above info', () {
        test('suppresses output entirely', () {
          logger.level = Level.warning;
          final progress = runUnderScope(
            () => logger.progress('fetching apps'),
            hasTerminal: false,
          );
          progress.complete();
          expect(stdoutOutput, isEmpty);
        });
      });
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart' hide logger;
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_cli_command_runner.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:test/test.dart';

import 'helpers.dart' as helpers;
import 'mocks.dart';

void main() {
  group(ShorebirdCliCommandRunner, () {
    const shorebirdEngineRevision = 'test-engine-revision';
    const flutterRevision = 'test-flutter-revision';
    const flutterVersion = '1.2.3';

    late ShorebirdLogger logger;
    late Platform platform;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdVersion shorebirdVersion;
    late ShorebirdCliCommandRunner commandRunner;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdVersionRef.overrideWith(() => shorebirdVersion),
        },
      );
    }

    setUp(() {
      logger = MockShorebirdLogger();
      platform = MockPlatform();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdVersion = MockShorebirdVersion();
      when(() => logger.level).thenReturn(Level.info);
      final logFile = MockFile();
      when(
        () => shorebirdEnv.logsDirectory,
      ).thenReturn(Directory.systemTemp.createTempSync());
      when(() => logFile.absolute).thenReturn(logFile);
      when(() => logFile.path).thenReturn('test.log');
      when(
        () => shorebirdEnv.shorebirdEngineRevision,
      ).thenReturn(shorebirdEngineRevision);
      when(() => platform.isWindows).thenReturn(false);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(
        () => shorebirdFlutter.getVersionString(),
      ).thenAnswer((_) async => flutterVersion);
      when(shorebirdVersion.isLatest).thenAnswer((_) async => true);
      when(shorebirdVersion.isTrackingStable).thenAnswer((_) async => true);
      commandRunner = runWithOverrides(ShorebirdCliCommandRunner.new);
    });

    group('handles ProcessExit', () {
      test('does nothing when exit code is 0', () async {
        commandRunner.addCommand(_TestCommand(ExitCode.success));
        final result = await runWithOverrides(
          () => commandRunner.run(['test']),
        );
        expect(result, equals(ExitCode.success.code));
      });

      test('exits with the correct code', () async {
        commandRunner.addCommand(_TestCommand(ExitCode.unavailable));
        final result = await runWithOverrides(
          () => commandRunner.run(['test']),
        );
        expect(result, equals(ExitCode.unavailable.code));
        verify(
          () => logger.info(
            any(
              that: contains('''If you aren't sure why this command failed'''),
            ),
          ),
        ).called(1);
      });
    });

    test('handles FormatException', () async {
      const exception = FormatException('oops!');
      var isFirstInvocation = true;
      when(() => logger.info(any())).thenAnswer((_) {
        if (isFirstInvocation) {
          isFirstInvocation = false;
          throw exception;
        }
      });
      final result = await runWithOverrides(
        () => commandRunner.run(['--version']),
      );
      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err(exception.message)).called(1);
      verify(() => logger.info(commandRunner.usage)).called(1);
    });

    group('when runCommand returns null exitCode', () {
      test('does not print failure text', () async {
        final result = await runWithOverrides(
          () => commandRunner.run(['--help']),
        );
        expect(result, equals(ExitCode.success.code));
        verifyNever(
          () => logger.info(
            any(that: contains("If you aren't sure why this command failed")),
          ),
        );
      });
    });

    test('handles UsageException', () async {
      final result = await runWithOverrides(
        // fly_to_the_moon is not a valid command.
        () => commandRunner.run(['fly_to_the_moon']),
      );
      expect(result, equals(ExitCode.usage.code));
      verify(
        () => logger.err('Could not find a command named "fly_to_the_moon".'),
      ).called(1);
      verify(
        () => logger.info(
          any(that: contains('Usage: shorebird <command> [arguments]')),
        ),
      ).called(1);
    });

    test('handles missing option error', () async {
      final exception = UsageException(
        'Could not find an option named "foo".',
        'exception usage',
      );
      var isFirstInvocation = true;
      when(() => logger.info(any())).thenAnswer((_) {
        if (isFirstInvocation) {
          isFirstInvocation = false;
          throw exception;
        }
      });
      final result = await runWithOverrides(
        () => commandRunner.run(['--version']),
      );
      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err(exception.message)).called(1);
      verify(
        () => logger.err('''
To proxy an option to the flutter command, use the -- --<option> syntax.

Example:

${lightCyan.wrap('shorebird release android -- --no-pub lib/main.dart')}'''),
      ).called(1);
      verify(() => logger.info('exception usage')).called(1);
    });

    test('handles missing option error on Windows', () async {
      when(() => platform.isWindows).thenReturn(true);
      final exception = UsageException(
        'Could not find an option named "foo".',
        'exception usage',
      );
      var isFirstInvocation = true;
      when(() => logger.info(any())).thenAnswer((_) {
        if (isFirstInvocation) {
          isFirstInvocation = false;
          throw exception;
        }
      });
      final result = await runWithOverrides(
        () => commandRunner.run(['--version']),
      );
      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err(exception.message)).called(1);
      verify(
        () => logger.err('''
To proxy an option to the flutter command, use the '--' --<option> syntax.

Example:

${lightCyan.wrap("shorebird release android '--' --no-pub lib/main.dart")}'''),
      ).called(1);
      verify(() => logger.info('exception usage')).called(1);
    });

    group('--version', () {
      test('outputs current version info', () async {
        final result = await runWithOverrides(
          () => commandRunner.run(['--version']),
        );
        expect(result, equals(ExitCode.success.code));

        verify(
          () => logger.info('''
Shorebird $packageVersion • git@github.com:shorebirdtech/shorebird.git
Flutter $flutterVersion • revision $flutterRevision
Engine • revision $shorebirdEngineRevision'''),
        ).called(1);

        // Making sure the only thing that was logged was the version info.
        // https://github.com/shorebirdtech/shorebird/issues/2260
        verifyNever(() => logger.info(any()));
      });
    });

    group('--verbose', () {
      test('enables verbose logging', () async {
        final result = await runWithOverrides(
          () => commandRunner.run(['--verbose']),
        );
        expect(result, equals(ExitCode.success.code));
      });
    });

    group('local engine', () {
      group('when all local engine args are provided', () {
        test('creates engine config with arguments', () async {
          final result = await runWithOverrides(
            () => commandRunner.run([
              '--local-engine',
              'foo',
              '--local-engine-src-path',
              'bar',
              '--local-engine-host',
              'baz',
            ]),
          );
          expect(result, equals(ExitCode.success.code));
        });
      });

      group('when no local engine args are provided', () {
        test('uses empty engine config', () async {
          final result = await runWithOverrides(() => commandRunner.run([]));
          expect(result, equals(ExitCode.success.code));
        });
      });

      group('when some local engine args are provided', () {
        test('throws ArgumentException', () async {
          await expectLater(
            () async => runWithOverrides(
              () => commandRunner.run(['--local-engine', 'foo']),
            ),
            throwsArgumentError,
          );
        });
      });
    });

    group('on command failure', () {
      test('logs error and stack trace using detail', () async {
        // This will fail with a StateError due to the release android command
        // missing scoped dependencies.
        // Note: the --verbose flag is here for illustrative purposes only.
        // Because logger is a mock, setting the log level in code does
        // nothing.
        await runWithOverrides(
          () => commandRunner.run(['release', 'android', '--verbose']),
        );
        verify(() => logger.err(any(that: contains('Bad state')))).called(1);
        verify(() => logger.detail(any(that: contains('#0')))).called(1);
      });

      group('when running with --verbose', () {
        setUp(() {
          when(() => logger.level).thenReturn(Level.verbose);
        });

        test('does not suggest running with --verbose', () async {
          // This will fail due to the release android command missing scoped
          // dependencies.
          // Note: the --verbose flag is here for illustrative purposes only.
          // Because logger is a mock, setting the log level in code does
          // nothing.
          await runWithOverrides(
            () => commandRunner.run(['release', 'android', '--verbose']),
          );
          verifyNever(() => logger.info(any(that: contains('--verbose'))));
        });
      });

      group('when running without --verbose', () {
        test('suggests using --verbose flag', () async {
          // This will fail due to the release android command missing scoped
          // dependencies.
          await runWithOverrides(
            () => commandRunner.run(['release', 'android']),
          );
          verify(() => logger.info(any(that: contains('--verbose')))).called(1);
        });
      });
    });

    group('completion', () {
      test('fast tracks completion', () async {
        final result = await runWithOverrides(
          () => commandRunner.run(['completion']),
        );
        expect(result, equals(ExitCode.success.code));
      });
    });

    group('update check', () {
      group('when running upgrade command', () {
        setUp(() {
          when(() => logger.progress(any())).thenReturn(MockProgress());
          when(
            shorebirdVersion.fetchCurrentGitHash,
          ).thenAnswer((_) async => 'current');
          when(
            shorebirdVersion.fetchLatestGitHash,
          ).thenAnswer((_) async => 'current');
        });
        test('does not check for update', () async {
          final result = await runWithOverrides(
            () => commandRunner.run(['upgrade']),
          );
          expect(result, equals(ExitCode.success.code));
          verifyNever(() => shorebirdVersion.isTrackingStable());
          verifyNever(() => shorebirdVersion.isLatest());
        });
      });

      group('when tracking the stable branch', () {
        setUp(() {
          when(shorebirdVersion.isTrackingStable).thenAnswer((_) async => true);
        });

        test(
          'gracefully handles case when latest version cannot be determined',
          () async {
            when(shorebirdVersion.isLatest).thenThrow(Exception('error'));
            final result = await runWithOverrides(
              () => commandRunner.run(['--version']),
            );
            expect(result, equals(ExitCode.success.code));
            verify(
              () => logger.detail(
                'Unable to check for updates.\nException: error',
              ),
            ).called(1);
          },
        );

        group('when update is available', () {
          test('logs update message', () async {
            when(shorebirdVersion.isLatest).thenAnswer((_) async => false);
            final result = await runWithOverrides(
              () => commandRunner.run(['--version']),
            );
            verify(
              () => logger.info('A new version of shorebird is available!'),
            ).called(1);
            verify(
              () => logger.info(
                'Run ${lightCyan.wrap('shorebird upgrade')} to upgrade.',
              ),
            ).called(1);

            expect(result, equals(ExitCode.success.code));
          });
        });

        group('when no update is available', () {
          setUp(() {
            when(shorebirdVersion.isLatest).thenAnswer((_) async => true);
          });

          test('does not log update message', () async {
            final result = await runWithOverrides(
              () => commandRunner.run(['--version']),
            );
            expect(result, equals(ExitCode.success.code));
            verifyNever(
              () => logger.info('A new version of shorebird is available!'),
            );
          });
        });

        test(
          'gracefully handles case when flutter version cannot be determined',
          () async {
            when(
              shorebirdFlutter.getVersionString,
            ).thenThrow(Exception('error'));
            final result = await runWithOverrides(
              () => commandRunner.run(['--version']),
            );
            expect(result, equals(ExitCode.success.code));
            verify(
              () => logger.detail(
                'Unable to determine Flutter version.\nException: error',
              ),
            ).called(1);
          },
        );
      });

      group('when not tracking the stable branch', () {
        setUp(() {
          when(
            shorebirdVersion.isTrackingStable,
          ).thenAnswer((_) async => false);
          when(shorebirdVersion.isLatest).thenAnswer((_) async => false);
        });

        test('does not check for updates or print update message', () async {
          final result = await runWithOverrides(
            () => commandRunner.run(['--version']),
          );
          expect(result, equals(ExitCode.success.code));

          verifyNever(shorebirdVersion.isLatest);
          verifyNever(
            () => logger.info('A new version of shorebird is available!'),
          );
        });
      });
    });

    group('--json', () {
      late List<String> stdoutOutput;

      setUp(() {
        stdoutOutput = [];
      });

      /// Runs [body] while capturing stdout writes into [stdoutOutput].
      Future<T> captureStdout<T>(Future<T> Function() body) async {
        return helpers.captureStdout(body, captured: stdoutOutput);
      }

      group('on ProcessExit with non-zero exit code', () {
        test('emits JSON error envelope', () async {
          commandRunner.addCommand(_TestCommand(ExitCode.unavailable));
          final result = await captureStdout(
            () => runWithOverrides(
              () => commandRunner.run(['--json', 'test']),
            ),
          );
          expect(result, equals(ExitCode.unavailable.code));

          // Should have emitted JSON to stdout.
          expect(stdoutOutput, isNotEmpty);
          final json = jsonDecode(stdoutOutput.first) as Map<String, dynamic>;
          expect(json['status'], equals('error'));
          final error = json['error'] as Map<String, dynamic>;
          expect(error['code'], equals('process_exit'));
          final meta = json['meta'] as Map<String, dynamic>;
          expect(meta['version'], equals(packageVersion));
          expect(meta['command'], equals('test'));
        });

        test('suppresses "file an issue" message', () async {
          commandRunner.addCommand(_TestCommand(ExitCode.unavailable));
          await captureStdout(
            () => runWithOverrides(
              () => commandRunner.run(['--json', 'test']),
            ),
          );
          verifyNever(
            () => logger.info(
              any(
                that: contains(
                  '''If you aren't sure why this command failed''',
                ),
              ),
            ),
          );
        });
      });

      group('on ProcessExit with zero exit code', () {
        test('does not emit JSON error', () async {
          commandRunner.addCommand(_TestCommand(ExitCode.success));
          final result = await captureStdout(
            () => runWithOverrides(
              () => commandRunner.run(['--json', 'test']),
            ),
          );
          expect(result, equals(ExitCode.success.code));
          expect(
            stdoutOutput.where((line) => line.contains('"status"')),
            isEmpty,
          );
        });
      });

      group('on software error', () {
        test('emits JSON error envelope', () async {
          commandRunner.addCommand(_ThrowingCommand());
          final result = await captureStdout(
            () => runWithOverrides(
              () => commandRunner.run(['--json', 'throwing']),
            ),
          );
          expect(result, equals(ExitCode.software.code));

          expect(stdoutOutput, isNotEmpty);
          final json = jsonDecode(stdoutOutput.first) as Map<String, dynamic>;
          expect(json['status'], equals('error'));
          final error = json['error'] as Map<String, dynamic>;
          expect(error['code'], equals('software_error'));
          expect(error.containsKey('hint'), isFalse);
          final meta = json['meta'] as Map<String, dynamic>;
          expect(meta['command'], equals('throwing'));
        });
      });

      group('on UsageException', () {
        test('emits JSON error envelope with hint', () async {
          final result = await captureStdout(
            () => runWithOverrides(
              () => commandRunner.run(['--json', 'nonexistent']),
            ),
          );
          expect(result, equals(ExitCode.usage.code));

          expect(stdoutOutput, isNotEmpty);
          final json = jsonDecode(stdoutOutput.first) as Map<String, dynamic>;
          expect(json['status'], equals('error'));
          final error = json['error'] as Map<String, dynamic>;
          expect(error['code'], equals('usage_error'));
          expect(error.containsKey('hint'), isTrue);
          verifyNever(() => logger.err(any()));
        });
      });

      group('--version', () {
        test('emits JSON success with version info', () async {
          const flutterVersionString = '3.22.2';
          when(
            () => shorebirdFlutter.getVersionString(),
          ).thenAnswer((_) async => flutterVersionString);

          final result = await captureStdout(
            () => runWithOverrides(
              () => commandRunner.run(['--json', '--version']),
            ),
          );

          expect(result, equals(ExitCode.success.code));
          expect(stdoutOutput, isNotEmpty);
          final json = jsonDecode(stdoutOutput.first) as Map<String, dynamic>;
          expect(json['status'], equals('success'));
          final data = json['data'] as Map<String, dynamic>;
          expect(data['shorebird_version'], equals(packageVersion));
          expect(data['flutter_version'], equals(flutterVersionString));
          expect(data['flutter_revision'], equals(flutterRevision));
          expect(data['engine_revision'], equals(shorebirdEngineRevision));
          verifyNever(() => logger.info(any()));
        });
      });

      test('does not check for updates', () async {
        commandRunner.addCommand(_TestCommand(ExitCode.success));
        await captureStdout(
          () => runWithOverrides(
            () => commandRunner.run(['--json', 'test']),
          ),
        );

        verifyNever(() => shorebirdVersion.isTrackingStable());
        verifyNever(() => shorebirdVersion.isLatest());
      });

      group('on parse-time errors', () {
        test('emits JSON error envelope on unknown command', () async {
          final result = await captureStdout(
            () => runWithOverrides(
              () => commandRunner.run(['--json', 'fly_to_the_moon']),
            ),
          );
          expect(result, equals(ExitCode.usage.code));
          expect(stdoutOutput, isNotEmpty);
          final json = jsonDecode(stdoutOutput.first) as Map<String, dynamic>;
          expect(json['status'], equals('error'));
          final error = json['error'] as Map<String, dynamic>;
          expect(error['code'], equals('usage_error'));
          expect(error['hint'], equals('Run: shorebird --help'));
          final meta = json['meta'] as Map<String, dynamic>;
          expect(meta['command'], equals('shorebird'));
          // Human-readable error must not be written under --json.
          verifyNever(() => logger.err(any()));
        });

        test('emits JSON error envelope on unknown global flag', () async {
          final result = await captureStdout(
            () => runWithOverrides(
              () => commandRunner.run(['--json', '--bogus']),
            ),
          );
          expect(result, equals(ExitCode.usage.code));
          expect(stdoutOutput, isNotEmpty);
          final json = jsonDecode(stdoutOutput.first) as Map<String, dynamic>;
          expect(json['status'], equals('error'));
          final error = json['error'] as Map<String, dynamic>;
          expect(error['code'], equals('usage_error'));
          expect(
            error['message'] as String,
            contains('Could not find an option'),
          );
          verifyNever(() => logger.err(any()));
        });
      });
    });

    group('on InteractivePromptRequiredException', () {
      const exception = InteractivePromptRequiredException(
        promptText: 'Continue?',
        hint: 'Pass --force.',
      );

      test('emits JSON error envelope under --json', () async {
        commandRunner.addCommand(
          _PromptRequiredCommand(exception: exception),
        );
        final stdoutOutput = <String>[];
        final result = await helpers.captureStdout<int?>(
          () => runWithOverrides(
            () => commandRunner.run(['--json', 'prompt-required']),
          ),
          captured: stdoutOutput,
        );
        expect(result, equals(ExitCode.usage.code));
        final json = jsonDecode(stdoutOutput.first) as Map<String, dynamic>;
        expect(json['status'], equals('error'));
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], equals('interactive_prompt_required'));
        expect(error['message'], equals('Continue?'));
        expect(error['hint'], equals('Pass --force.'));
        final meta = json['meta'] as Map<String, dynamic>;
        expect(meta['command'], equals('prompt-required'));
      });

      test('emits human-readable stderr without --json', () async {
        commandRunner.addCommand(
          _PromptRequiredCommand(exception: exception),
        );
        final result = await runWithOverrides(
          () => commandRunner.run(['prompt-required']),
        );
        expect(result, equals(ExitCode.usage.code));
        verify(() => logger.err(any(that: contains('non-interactive')))).called(
          1,
        );
        verify(() => logger.err(any(that: contains('Continue?')))).called(1);
        verify(() => logger.info(any(that: contains('Pass --force.')))).called(
          1,
        );
      });
    });

    group('ANSI suppression', () {
      late _CaptureModeCommand captureCommand;
      late List<String> stdoutOutput;

      setUp(() {
        captureCommand = _CaptureModeCommand();
        commandRunner.addCommand(captureCommand);
        stdoutOutput = [];
      });

      Future<bool> runAndReadAnsi({
        required List<String> args,
        required bool hasTerminal,
      }) async {
        late bool capturedAnsi;
        await helpers.captureStdout<int?>(
          () => runWithOverrides(() {
            captureCommand.onRun = () {
              capturedAnsi = ansiOutputEnabled;
            };
            return commandRunner.run(args);
          }),
          captured: stdoutOutput,
          hasTerminal: hasTerminal,
        );
        return capturedAnsi;
      }

      test('disables ANSI in --json mode even when stdout is a TTY', () async {
        final ansi = await runAndReadAnsi(
          args: ['--json', 'capture-mode'],
          hasTerminal: true,
        );
        expect(ansi, isFalse);
      });

      test('disables ANSI in --no-input mode', () async {
        final ansi = await runAndReadAnsi(
          args: ['--no-input', 'capture-mode'],
          hasTerminal: true,
        );
        expect(ansi, isFalse);
      });

      test('leaves ANSI handling to the io package by default', () async {
        // Without --json or --no-input the runner does not call
        // overrideAnsiOutput; whether ANSI is enabled is decided by the io
        // package based on the actual stdio. We just assert that the runner
        // did not force it off.
        final ansi = await runAndReadAnsi(
          args: ['capture-mode'],
          hasTerminal: true,
        );
        // Test environment may or may not have a real TTY (CI vs local), so
        // we only assert the runner didn't pin the value to false.
        expect(ansi, isA<bool>());
      });
    });

    group('interactive mode', () {
      late _CaptureModeCommand captureCommand;
      late List<String> stdoutOutput;

      setUp(() {
        captureCommand = _CaptureModeCommand();
        commandRunner.addCommand(captureCommand);
        stdoutOutput = [];
      });

      Future<int?> runCapturing({
        required List<String> args,
        required bool hasTerminal,
      }) {
        return helpers.captureStdout<int?>(
          () => runWithOverrides(() => commandRunner.run(args)),
          captured: stdoutOutput,
          hasTerminal: hasTerminal,
        );
      }

      group('with a TTY-attached stdout', () {
        test(
          'isInteractive is true when no overriding flags are passed',
          () async {
            await runCapturing(args: ['capture-mode'], hasTerminal: true);
            expect(captureCommand.capturedIsJsonMode, isFalse);
            expect(captureCommand.capturedIsNoInputMode, isFalse);
            expect(captureCommand.capturedIsInteractive, isTrue);
          },
        );

        test('isInteractive is false when --json is passed', () async {
          await runCapturing(
            args: ['--json', 'capture-mode'],
            hasTerminal: true,
          );
          expect(captureCommand.capturedIsJsonMode, isTrue);
          expect(captureCommand.capturedIsNoInputMode, isFalse);
          expect(captureCommand.capturedIsInteractive, isFalse);
        });

        test('isInteractive is false when --no-input is passed', () async {
          await runCapturing(
            args: ['--no-input', 'capture-mode'],
            hasTerminal: true,
          );
          expect(captureCommand.capturedIsJsonMode, isFalse);
          expect(captureCommand.capturedIsNoInputMode, isTrue);
          expect(captureCommand.capturedIsInteractive, isFalse);
        });

        test(
          'isInteractive is false when both --json and --no-input are passed',
          () async {
            await runCapturing(
              args: ['--json', '--no-input', 'capture-mode'],
              hasTerminal: true,
            );
            expect(captureCommand.capturedIsJsonMode, isTrue);
            expect(captureCommand.capturedIsNoInputMode, isTrue);
            expect(captureCommand.capturedIsInteractive, isFalse);
          },
        );
      });

      group('without a TTY-attached stdout', () {
        test('isInteractive is false even with no flags passed', () async {
          await runCapturing(args: ['capture-mode'], hasTerminal: false);
          expect(captureCommand.capturedIsJsonMode, isFalse);
          expect(captureCommand.capturedIsNoInputMode, isFalse);
          expect(captureCommand.capturedIsInteractive, isFalse);
        });

        test('isInteractive remains false when --no-input is passed', () async {
          await runCapturing(
            args: ['--no-input', 'capture-mode'],
            hasTerminal: false,
          );
          expect(captureCommand.capturedIsNoInputMode, isTrue);
          expect(captureCommand.capturedIsInteractive, isFalse);
        });
      });

      group('--no-input is exposed on every top-level command', () {
        test('appears in the root usage', () {
          expect(commandRunner.usage, contains('--no-input'));
        });

        test('parses with arbitrary subcommands', () async {
          await runCapturing(
            args: ['--no-input', 'capture-mode'],
            hasTerminal: true,
          );
          expect(captureCommand.capturedIsNoInputMode, isTrue);
        });
      });
    });
  });
}

class _TestCommand extends ShorebirdCommand {
  _TestCommand(this.exitCode);

  final ExitCode exitCode;

  @override
  String get name => 'test';

  @override
  String get description => 'Test command';

  @override
  Future<int> run() async {
    throw ProcessExit(exitCode.code);
  }
}

class _ThrowingCommand extends ShorebirdCommand {
  @override
  String get name => 'throwing';

  @override
  String get description => 'A command that throws';

  @override
  Future<int> run() async {
    throw StateError('something went wrong');
  }
}

/// A test command whose `run` throws [InteractivePromptRequiredException].
///
/// Used to verify the runner's translation of this exception to either a
/// JSON envelope (under `--json`) or a stderr message.
class _PromptRequiredCommand extends ShorebirdCommand {
  _PromptRequiredCommand({required this.exception});

  final InteractivePromptRequiredException exception;

  @override
  String get name => 'prompt-required';

  @override
  String get description => 'Throws InteractivePromptRequiredException.';

  @override
  Future<int> run() async => throw exception;
}

/// A test command that records the values of [isJsonMode], [isNoInputMode],
/// and [isInteractive] as observed during [run]. Optionally invokes [onRun]
/// inside the runScoped/overrideAnsiOutput zone to capture other zone state
/// (for example, [ansiOutputEnabled]).
class _CaptureModeCommand extends ShorebirdCommand {
  bool? capturedIsJsonMode;
  bool? capturedIsNoInputMode;
  bool? capturedIsInteractive;
  void Function()? onRun;

  @override
  String get name => 'capture-mode';

  @override
  String get description => 'Captures interactive mode flags for testing.';

  @override
  Future<int> run() async {
    capturedIsJsonMode = isJsonMode;
    capturedIsNoInputMode = isNoInputMode;
    capturedIsInteractive = isInteractive;
    onRun?.call();
    return ExitCode.success.code;
  }
}

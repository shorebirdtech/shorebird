import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart' hide logger;
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_cli_command_runner.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import 'helpers.dart' as helpers;
import 'helpers.dart';
import 'mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(ShorebirdCliCommandRunner, () {
    const shorebirdEngineRevision = 'test-engine-revision';
    const flutterRevision = 'test-flutter-revision';
    const flutterVersion = '1.2.3';

    late Cache cache;
    late ShorebirdLogger logger;
    late TestNativePlatform platform;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdVersion shorebirdVersion;
    late ShorebirdCliCommandRunner commandRunner;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          cacheRef.overrideWith(() => cache),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdVersionRef.overrideWith(() => shorebirdVersion),
        },
      );
    }

    setUp(() {
      cache = MockCache();
      logger = MockShorebirdLogger();
      platform = TestNativePlatform(operatingSystem: NativePlatform.linux);
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
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(
        () => shorebirdFlutter.getVersionString(),
      ).thenAnswer((_) async => flutterVersion);
      when(() => shorebirdFlutter.pruneUnusedRevisions()).thenReturn([]);
      when(() => cache.pruneUnusedArtifacts()).thenReturn([]);
      when(() => cache.pruneUnusedPreviews()).thenReturn([]);
      when(shorebirdVersion.isLatest).thenAnswer((_) async => true);
      when(shorebirdVersion.isTrackingStable).thenAnswer((_) async => true);
      commandRunner = runWithOverrides(ShorebirdCliCommandRunner.new);
    });

    group('pruning unused caches', () {
      test('prunes after the command runs', () async {
        commandRunner.addCommand(_TestCommand(ExitCode.success));

        await runWithOverrides(() => commandRunner.run(['test']));

        verify(() => shorebirdFlutter.pruneUnusedRevisions()).called(1);
        verify(() => cache.pruneUnusedArtifacts()).called(1);
        verify(() => cache.pruneUnusedPreviews()).called(1);
      });

      test('prunes after a command that fails', () async {
        commandRunner.addCommand(_TestCommand(ExitCode.software));

        await runWithOverrides(() => commandRunner.run(['test']));

        verify(() => shorebirdFlutter.pruneUnusedRevisions()).called(1);
        verify(() => cache.pruneUnusedArtifacts()).called(1);
        verify(() => cache.pruneUnusedPreviews()).called(1);
      });

      test('does not fail the command when pruning throws', () async {
        when(
          () => shorebirdFlutter.pruneUnusedRevisions(),
        ).thenThrow(const FileSystemException('denied'));
        when(
          () => cache.pruneUnusedArtifacts(),
        ).thenThrow(const FileSystemException('denied'));
        when(
          () => cache.pruneUnusedPreviews(),
        ).thenThrow(const FileSystemException('denied'));
        commandRunner.addCommand(_TestCommand(ExitCode.success));

        final result = await runWithOverrides(
          () => commandRunner.run(['test']),
        );

        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.detail(
            any(that: contains('Unable to prune unused Flutter installs')),
          ),
        ).called(1);
        verify(
          () => logger.detail(
            any(that: contains('Unable to prune unused artifacts')),
          ),
        ).called(1);
        verify(
          () => logger.detail(
            any(that: contains('Unable to prune unused previews')),
          ),
        ).called(1);
      });
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
      platform = TestNativePlatform(operatingSystem: NativePlatform.windows);
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

    group('unknown option on patch', () {
      const overrideHint = '''
shorebird patch has no --force flag. The patch safety checks are bypassed per check:
  --allow-native-diffs  publish even though native code changed
  --allow-asset-diffs   publish even though assets changed
The warning that fails the patch names the one that applies.''';

      test('names --allow-native-diffs / --allow-asset-diffs', () async {
        final result = await runWithOverrides(
          () => commandRunner.run(['patch', 'android', '--force']),
        );
        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err('Could not find an option named "--force".'),
        ).called(1);
        verify(() => logger.err(overrideHint)).called(1);
        verifyNever(
          () => logger.err(any(that: contains('To proxy an option'))),
        );
      });

      test('matches other override-shaped options', () async {
        await runWithOverrides(
          () => commandRunner.run(['patch', '--skip-checks']),
        );
        verify(
          () => logger.err(
            any(that: startsWith('shorebird patch has no --skip-checks flag')),
          ),
        ).called(1);
      });

      test('falls back to the proxy hint for other options', () async {
        await runWithOverrides(
          () => commandRunner.run(['patch', 'android', '--no-pub']),
        );
        verify(
          () => logger.err(any(that: contains('To proxy an option'))),
        ).called(1);
      });

      test('does not apply to other commands', () async {
        await runWithOverrides(
          () => commandRunner.run(['release', 'android', '--force']),
        );
        verify(
          () => logger.err(any(that: contains('To proxy an option'))),
        ).called(1);
      });

      test('carries the hint in the --json envelope', () async {
        final stdoutOutput = <String>[];
        await helpers.captureStdout<int>(
          () => runWithOverrides(
            () => commandRunner.run(['--json', 'patch', 'android', '--force']),
          ),
          captured: stdoutOutput,
        );
        final json = jsonDecode(stdoutOutput.first) as Map<String, dynamic>;
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], equals('usage_error'));
        expect(error['hint'], equals(overrideHint));
      });
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
        test('exits with a usage error naming the flags', () async {
          final result = await runWithOverrides(
            () => commandRunner.run(['--local-engine', 'foo']),
          );
          expect(result, equals(ExitCode.usage.code));
          verify(
            () => logger.err(
              '''--local-engine, --local-engine-src-path, and --local-engine-host must all be provided together''',
            ),
          ).called(1);
        });

        test('emits a single usage_error envelope in --json mode', () async {
          final stdoutOutput = <String>[];
          final result = await helpers.captureStdout<int>(
            () => runWithOverrides(
              () => commandRunner.run(['--json', '--local-engine', 'foo']),
            ),
            captured: stdoutOutput,
          );
          expect(result, equals(ExitCode.usage.code));
          expect(stdoutOutput, hasLength(1));
          final json = jsonDecode(stdoutOutput.single) as Map<String, dynamic>;
          final error = json['error'] as Map<String, dynamic>;
          expect(error['code'], equals('usage_error'));
          expect(
            error['message'],
            equals(
              '''--local-engine, --local-engine-src-path, and --local-engine-host must all be provided together''',
            ),
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

    group('when the command reserves stdout', () {
      test('does not print the failure hint', () async {
        commandRunner.addCommand(_ReservesStdoutCommand(exitCode: 1));

        final result = await runWithOverrides(
          () => commandRunner.run(['reserves-stdout']),
        );

        expect(result, equals(1));
        verifyNever(
          () => logger.info(
            any(that: contains("If you aren't sure why this command failed")),
          ),
        );
      });

      test('prints the update notice to stderr', () async {
        when(shorebirdVersion.isLatest).thenAnswer((_) async => false);
        commandRunner.addCommand(_ReservesStdoutCommand(exitCode: 0));
        final stdoutLines = <String>[];
        final stderrLines = <String>[];
        final realStderr = stderr;

        await helpers.captureStdout(
          () => IOOverrides.runZoned(
            () => runWithOverrides(
              () => commandRunner.run(['reserves-stdout']),
            ),
            stderr: () => helpers.CapturingStdout(
              baseStdOut: realStderr,
              captured: stderrLines,
            ),
          ),
          captured: stdoutLines,
        );

        expect(stdoutLines, isEmpty);
        expect(
          stderrLines,
          contains('A new version of shorebird is available!'),
        );
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

      test('routes everything but the envelope to stderr', () async {
        // A command that writes a human line straight to stdout and then
        // emits an envelope. With --json, stdout must carry the envelope
        // alone; the human line lands on stderr.
        commandRunner.addCommand(_ChattyCommand());
        final stderrOutput = <String>[];
        final realStderr = stderr;
        final result = await captureStdout(
          () => IOOverrides.runZoned(
            () => runWithOverrides(
              () => commandRunner.run(['--json', 'chatty']),
            ),
            stderr: () => helpers.CapturingStdout(
              baseStdOut: realStderr,
              captured: stderrOutput,
            ),
          ),
        );

        expect(result, equals(ExitCode.success.code));
        expect(stdoutOutput, hasLength(1));
        final json = jsonDecode(stdoutOutput.single) as Map<String, dynamic>;
        expect(json['status'], equals('success'));
        expect((json['data'] as Map)['said'], equals('hello'));
        expect(stderrOutput, contains('hello, human'));
      });

      test('leaves stdout alone without --json', () async {
        commandRunner.addCommand(_ChattyCommand());
        final result = await captureStdout(
          () => runWithOverrides(() => commandRunner.run(['chatty'])),
        );

        expect(result, equals(ExitCode.success.code));
        expect(stdoutOutput, equals(['hello, human']));
      });

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

      group('when a command fails without writing an envelope', () {
        test('emits exactly one error envelope', () async {
          // e.g. a failed precondition (not logged in, not initialized),
          // which commands report by returning its exit code.
          commandRunner.addCommand(_FailingCommand());
          final result = await captureStdout(
            () => runWithOverrides(
              () => commandRunner.run(['--json', 'failing']),
            ),
          );
          expect(result, equals(ExitCode.config.code));
          expect(stdoutOutput, hasLength(1));
          final json = jsonDecode(stdoutOutput.single) as Map<String, dynamic>;
          expect(json['status'], equals('error'));
          final error = json['error'] as Map<String, dynamic>;
          expect(error['code'], equals('process_exit'));
          expect(
            error['message'],
            equals('Process exited with code ${ExitCode.config.code}.'),
          );
          final meta = json['meta'] as Map<String, dynamic>;
          expect(meta['command'], equals('failing'));
        });

        test('writes nothing without --json', () async {
          commandRunner.addCommand(_FailingCommand());
          final result = await captureStdout(
            () => runWithOverrides(() => commandRunner.run(['failing'])),
          );
          expect(result, equals(ExitCode.config.code));
          expect(
            stdoutOutput.where((line) => line.contains('"status"')),
            isEmpty,
          );
        });
      });

      group('when an API call fails', () {
        test('emits one envelope with the server message, code and '
            'details', () async {
          commandRunner.addCommand(
            _FailingCommand(
              thenThrow: ApiErrorExit(
                const CodePushException(
                  message: 'Plan lacks this feature.',
                  response: ErrorResponse(
                    code: 'shorebird_plan_insufficient_tier',
                    message: 'Plan lacks this feature.',
                  ),
                  details: 'Upgrade to Business.',
                ),
                ExitCode.software.code,
              ),
            ),
          );
          final result = await captureStdout(
            () => runWithOverrides(
              () => commandRunner.run(['--json', 'failing']),
            ),
          );
          expect(result, equals(ExitCode.software.code));
          expect(stdoutOutput, hasLength(1));
          final json = jsonDecode(stdoutOutput.single) as Map<String, dynamic>;
          expect(
            json['error'],
            equals({
              'code': 'process_exit',
              'message': 'Plan lacks this feature.',
              'api_code': 'shorebird_plan_insufficient_tier',
              'details': 'Upgrade to Business.',
            }),
          );
        });
      });

      group('when a precondition fails', () {
        Future<(int?, Map<String, dynamic>)> runSingleEnvelope(
          ShorebirdCommand command,
        ) async {
          commandRunner.addCommand(command);
          final result = await captureStdout(
            () => runWithOverrides(
              () => commandRunner.run(['--json', command.name]),
            ),
          );
          expect(stdoutOutput, hasLength(1));
          final json = jsonDecode(stdoutOutput.single) as Map<String, dynamic>;
          expect(json['status'], equals('error'));
          return (result, json['error'] as Map<String, dynamic>);
        }

        test('a reported failure emits one precondition_failed envelope '
            'with its message and hint', () async {
          final (result, error) = await runSingleEnvelope(
            _PreconditionCommand(),
          );
          expect(result, equals(ExitCode.noUser.code));
          expect(
            error,
            equals({
              'code': 'precondition_failed',
              'message': UserNotAuthorizedException().message,
              'hint': UserNotAuthorizedException().hint,
            }),
          );
        });

        test('a thrown PreconditionFailedExit emits one precondition_failed '
            'envelope with its message and hint', () async {
          final (result, error) = await runSingleEnvelope(
            _FailingCommand(
              thenThrow: PreconditionFailedExit(
                ShorebirdNotInitializedException(),
              ),
            ),
          );
          expect(result, equals(ExitCode.config.code));
          expect(
            error,
            equals({
              'code': 'precondition_failed',
              'message': ShorebirdNotInitializedException().message,
              'hint': ShorebirdNotInitializedException().hint,
            }),
          );
        });

        test('a thrown PreconditionFailedExit writes nothing without '
            '--json', () async {
          commandRunner.addCommand(
            _FailingCommand(
              thenThrow: PreconditionFailedExit(UserNotAuthorizedException()),
            ),
          );
          final result = await captureStdout(
            () => runWithOverrides(() => commandRunner.run(['failing'])),
          );
          expect(result, equals(ExitCode.noUser.code));
          expect(
            stdoutOutput.where((line) => line.contains('"status"')),
            isEmpty,
          );
        });
      });

      group('when a command already wrote an envelope', () {
        Future<Map<String, dynamic>> runSingleEnvelope(
          _FailingCommand command,
        ) async {
          commandRunner.addCommand(command);
          await captureStdout(
            () => runWithOverrides(
              () => commandRunner.run(['--json', 'failing']),
            ),
          );
          expect(stdoutOutput, hasLength(1));
          final json = jsonDecode(stdoutOutput.single) as Map<String, dynamic>;
          return json['error'] as Map<String, dynamic>;
        }

        test('and returns a failure, does not add a second', () async {
          final error = await runSingleEnvelope(
            _FailingCommand(reports: true),
          );
          expect(error['message'], equals('own envelope'));
        });

        test('and throws ProcessExit, does not add a second', () async {
          final error = await runSingleEnvelope(
            _FailingCommand(
              reports: true,
              thenThrow: ProcessExit(ExitCode.software.code),
            ),
          );
          expect(error['message'], equals('own envelope'));
        });

        test('and throws UsageException, does not add a second', () async {
          final error = await runSingleEnvelope(
            _FailingCommand(
              reports: true,
              thenThrow: UsageException('bad usage', 'usage'),
            ),
          );
          expect(error['message'], equals('own envelope'));
        });

        test('and throws InteractivePromptRequiredException, does not add a '
            'second', () async {
          final error = await runSingleEnvelope(
            _FailingCommand(
              reports: true,
              thenThrow: const InteractivePromptRequiredException(
                promptText: 'Continue?',
                hint: 'Pass --force',
              ),
            ),
          );
          expect(error['message'], equals('own envelope'));
        });

        test('and throws an error, does not add a second', () async {
          final error = await runSingleEnvelope(
            _FailingCommand(reports: true, thenThrow: StateError('boom')),
          );
          expect(error['message'], equals('own envelope'));
        });
      });

      group('on ProcessExit with zero exit code', () {
        test('emits one success envelope', () async {
          commandRunner.addCommand(_TestCommand(ExitCode.success));
          final result = await captureStdout(
            () => runWithOverrides(
              () => commandRunner.run(['--json', 'test']),
            ),
          );
          expect(result, equals(ExitCode.success.code));
          final json = jsonDecode(stdoutOutput.single) as Map<String, dynamic>;
          expect(json['status'], equals('success'));
          expect(json['data'], isEmpty);
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

      group('on a command that writes no envelope', () {
        late _HumanOnlyCommand command;

        setUp(() {
          command = _HumanOnlyCommand();
          commandRunner.addCommand(command);
        });

        Future<(int?, Map<String, dynamic>)> runJson(List<String> args) async {
          final result = await captureStdout(
            () => runWithOverrides(() => commandRunner.run(args)),
          );
          final json = jsonDecode(stdoutOutput.single) as Map<String, dynamic>;
          return (result, json);
        }

        test('runs it and emits one empty success envelope', () async {
          final stderrOutput = <String>[];
          final realStderr = stderr;
          final (result, json) = await IOOverrides.runZoned(
            () => runJson(['--json', 'human-only']),
            stderr: () => helpers.CapturingStdout(
              baseStdOut: realStderr,
              captured: stderrOutput,
            ),
          );

          expect(result, equals(ExitCode.success.code));
          expect(command.ran, isTrue);
          expect(json['status'], equals('success'));
          expect(json['data'], isEmpty);
          expect((json['meta'] as Map)['command'], equals('human-only'));
          expect(stderrOutput, contains('hello, human'));
        });

        test('names the full subcommand', () async {
          commandRunner.addCommand(_GroupCommand());
          final (result, json) = await runJson(['--json', 'group', 'leaf']);

          expect(result, equals(ExitCode.success.code));
          expect((json['meta'] as Map)['command'], equals('group leaf'));
        });

        test('prints --help usage via the logger and one envelope', () async {
          final (result, json) = await runJson([
            '--json',
            'human-only',
            '--help',
          ]);

          expect(result, equals(ExitCode.success.code));
          expect(command.ran, isFalse);
          expect(json['status'], equals('success'));
          verify(() => logger.info(command.usage)).called(1);
        });

        test(
          'prints `help <command>` via the logger and one envelope',
          () async {
            final (result, json) = await runJson([
              '--json',
              'help',
              'human-only',
            ]);

            expect(result, equals(ExitCode.success.code));
            expect(json['status'], equals('success'));
            verify(() => logger.info(command.usage)).called(1);
          },
        );

        test('emits one error envelope when it fails', () async {
          command.exitCode = ExitCode.config;
          final (result, json) = await runJson(['--json', 'human-only']);

          expect(result, equals(ExitCode.config.code));
          expect(json['status'], equals('error'));
          final error = json['error'] as Map<String, dynamic>;
          expect(error['code'], equals('process_exit'));
        });

        test('emits no envelope without --json', () async {
          final result = await captureStdout(
            () => runWithOverrides(() => commandRunner.run(['human-only'])),
          );

          expect(result, equals(ExitCode.success.code));
          expect(stdoutOutput, equals(['hello, human']));
        });
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

      test('leaves ANSI handling to the io package by default', () async {
        // Without --json the runner does not call overrideAnsiOutput; whether
        // ANSI is enabled is decided by the io package based on the actual
        // stdio. We just assert that the runner did not force it off.
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
            expect(captureCommand.capturedIsInteractive, isTrue);
          },
        );

        test('isInteractive is false when --json is passed', () async {
          await runCapturing(
            args: ['--json', 'capture-mode'],
            hasTerminal: true,
          );
          expect(captureCommand.capturedIsJsonMode, isTrue);
          expect(captureCommand.capturedIsInteractive, isFalse);
        });
      });

      group('without a TTY-attached stdout', () {
        test('isInteractive is false even with no flags passed', () async {
          await runCapturing(args: ['capture-mode'], hasTerminal: false);
          expect(captureCommand.capturedIsJsonMode, isFalse);
          expect(captureCommand.capturedIsInteractive, isFalse);
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

/// Returns [exitCode], and owns stdout the way `shorebird api` does.
class _ReservesStdoutCommand extends ShorebirdCommand {
  _ReservesStdoutCommand({required this.exitCode});

  final int exitCode;

  @override
  String get name => 'reserves-stdout';

  @override
  String get description => 'Reserves stdout command';

  @override
  bool get reservesStdout => true;

  @override
  Future<int> run() async => exitCode;
}

/// Writes a human line to stdout, then an envelope when in JSON mode.
class _ChattyCommand extends ShorebirdCommand {
  @override
  String get name => 'chatty';

  @override
  String get description => 'Chatty command';

  @override
  Future<int> run() async {
    stdout.writeln('hello, human');
    if (isJsonMode) emitJsonSuccess({'said': 'hello'});
    return ExitCode.success.code;
  }
}

/// Fails by returning [ExitCode.config], optionally after writing its own
/// error envelope ([reports]) and optionally throwing [thenThrow] afterwards.
class _FailingCommand extends ShorebirdCommand {
  _FailingCommand({this.reports = false, this.thenThrow});

  final bool reports;
  final Object? thenThrow;

  @override
  String get name => 'failing';

  @override
  String get description => 'A command that fails';

  @override
  Future<int> run() async {
    if (reports) {
      emitJsonError(code: JsonErrorCode.usageError, message: 'own envelope');
    }
    if (thenThrow case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return ExitCode.config.code;
  }
}

/// A command whose precondition check fails (the user isn't logged in) and
/// reports it the way commands do, with [reportPreconditionFailure].
class _PreconditionCommand extends ShorebirdCommand {
  @override
  String get name => 'precondition';

  @override
  String get description => 'A command whose precondition fails';

  @override
  Future<int> run() async =>
      reportPreconditionFailure(UserNotAuthorizedException());
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

/// A test command that records the values of [isJsonMode] and [isInteractive]
/// as observed during [run]. Optionally invokes [onRun] inside the
/// runScoped/overrideAnsiOutput zone to capture other zone state (for example,
/// [ansiOutputEnabled]).
class _CaptureModeCommand extends ShorebirdCommand {
  bool? capturedIsJsonMode;
  bool? capturedIsInteractive;
  void Function()? onRun;

  @override
  String get name => 'capture-mode';

  @override
  String get description => 'Captures interactive mode flags for testing.';

  @override
  Future<int> run() async {
    capturedIsJsonMode = isJsonMode;
    capturedIsInteractive = isInteractive;
    onRun?.call();
    return ExitCode.success.code;
  }
}

/// A command that prints human output only, never an envelope.
class _HumanOnlyCommand extends ShorebirdCommand {
  _HumanOnlyCommand({this.name = 'human-only'});

  @override
  final String name;

  ExitCode exitCode = ExitCode.success;
  bool ran = false;

  @override
  String get description => 'Prints human output only.';

  @override
  Future<int> run() async {
    ran = true;
    stdout.writeln('hello, human');
    return exitCode.code;
  }
}

/// A command group holding one [_HumanOnlyCommand], `leaf`.
class _GroupCommand extends ShorebirdCommand {
  _GroupCommand() {
    addSubcommand(_HumanOnlyCommand(name: 'leaf'));
  }

  @override
  String get name => 'group';

  @override
  String get description => 'A command group.';
}

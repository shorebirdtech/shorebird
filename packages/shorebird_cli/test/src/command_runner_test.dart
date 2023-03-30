import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_cli/src/engine_revision.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockProcessResult extends Mock implements ProcessResult {}

void main() {
  group('ShorebirdCliCommandRunner', () {
    late Logger logger;
    late ProcessResult processResult;
    late ShorebirdCliCommandRunner commandRunner;

    setUp(() {
      logger = _MockLogger();

      processResult = _MockProcessResult();
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      when(() => processResult.stdout).thenReturn(
        'Engine • revision $requiredFlutterEngineRevision',
      );

      commandRunner = ShorebirdCliCommandRunner(
        logger: logger,
        runProcess: (
          executable,
          arguments, {
          bool runInShell = false,
          String? workingDirectory,
        }) async {
          return processResult;
        },
      );
    });

    test('exits when Flutter is not installed', () async {
      const error = 'oops something went wrong';
      when(() => processResult.exitCode).thenReturn(1);
      when(() => processResult.stderr).thenReturn(error);

      final result = await commandRunner.run(['--version']);
      expect(result, equals(ExitCode.software.code));
      verify(() => logger.err(any(that: contains(error)))).called(1);
    });

    test('exits when unable to detect the Flutter engine revision', () async {
      when(() => processResult.exitCode).thenReturn(0);
      when(() => processResult.stdout).thenReturn(
        '''
Flutter 3.7.7 • channel stable •
Framework • revision 2ad6cd72c0 (12 days ago) • 2023-03-08 09:41:59 -0800
Tools • Dart 2.19.4 • DevTools 2.20.1
''',
      );

      final result = await commandRunner.run(['--version']);
      expect(result, equals(ExitCode.software.code));
      verify(
        () => logger.err(
          any(
            that: contains('Unable to determine the Flutter engine revision.'),
          ),
        ),
      ).called(1);
    });

    test('exits when there is an incompatible Flutter engine', () async {
      when(() => processResult.stdout).thenReturn(
        '''
Flutter 3.7.7 • channel stable •
Framework • revision 2ad6cd72c0 (12 days ago) • 2023-03-08 09:41:59 -0800
Engine • revision 639e313f99
Tools • Dart 2.19.4 • DevTools 2.20.1
''',
      );

      final result = await commandRunner.run(['--version']);
      expect(result, equals(ExitCode.software.code));
      verify(
        () => logger.err(
          any(
            that: contains(
              '''Shorebird only works with the latest stable channel at this time.''',
            ),
          ),
        ),
      ).called(1);
    });

    test('can be instantiated without an explicit analytics/logger instance',
        () {
      final commandRunner = ShorebirdCliCommandRunner();
      expect(commandRunner, isNotNull);
      expect(commandRunner, isA<CompletionCommandRunner<int>>());
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
      final result = await commandRunner.run(['--version']);
      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err(exception.message)).called(1);
      verify(() => logger.info(commandRunner.usage)).called(1);
    });

    test('handles UsageException', () async {
      final exception = UsageException('oops!', 'exception usage');
      var isFirstInvocation = true;
      when(() => logger.info(any())).thenAnswer((_) {
        if (isFirstInvocation) {
          isFirstInvocation = false;
          throw exception;
        }
      });
      final result = await commandRunner.run(['--version']);
      expect(result, equals(ExitCode.usage.code));
      verify(() => logger.err(exception.message)).called(1);
      verify(() => logger.info('exception usage')).called(1);
    });

    group('--version', () {
      test('outputs current version and engine revisions', () async {
        final result = await commandRunner.run(['--version']);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info(
            '''
Shorebird $packageVersion
Flutter Engine • revision $requiredFlutterEngineRevision
Shorebird Engine • revision $shorebirdEngineRevision''',
          ),
        ).called(1);
      });
    });

    group('--verbose', () {
      test('enables verbose logging', () async {
        final result = await commandRunner.run(['--verbose']);
        expect(result, equals(ExitCode.success.code));
      });
    });

    group('completion', () {
      test('fast tracks completion', () async {
        final result = await commandRunner.run(['completion']);
        expect(result, equals(ExitCode.success.code));
      });
    });
  });
}

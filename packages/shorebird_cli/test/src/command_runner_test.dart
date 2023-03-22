import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_cli/src/flutter_engine_revision.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockProcessResult extends Mock implements ProcessResult {}

class _MockProgress extends Mock implements Progress {}

class _MockPubUpdater extends Mock implements PubUpdater {}

const latestVersion = '0.0.0';

final updatePrompt = '''
${lightYellow.wrap('Update available!')} ${lightCyan.wrap(packageVersion)} \u2192 ${lightCyan.wrap(latestVersion)}
Run ${lightCyan.wrap('$executableName update')} to update''';

void main() {
  group('ShorebirdCliCommandRunner', () {
    late PubUpdater pubUpdater;
    late Logger logger;
    late ProcessResult processResult;
    late ShorebirdCliCommandRunner commandRunner;

    setUp(() {
      pubUpdater = _MockPubUpdater();

      when(
        () => pubUpdater.getLatestVersion(any()),
      ).thenAnswer((_) async => packageVersion);

      logger = _MockLogger();

      processResult = _MockProcessResult();
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      when(() => processResult.stdout).thenReturn(
        'Engine • revision $requiredFlutterEngineRevision',
      );

      commandRunner = ShorebirdCliCommandRunner(
        logger: logger,
        pubUpdater: pubUpdater,
        runProcess: (
          String executable,
          List<String> arguments, {
          bool runInShell = false,
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

    test('shows update message when newer version exists', () async {
      when(
        () => pubUpdater.getLatestVersion(any()),
      ).thenAnswer((_) async => latestVersion);

      final result = await commandRunner.run(['--version']);
      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info(updatePrompt)).called(1);
    });

    test(
      'Does not show update message when the shell calls the '
      'completion command',
      () async {
        when(
          () => pubUpdater.getLatestVersion(any()),
        ).thenAnswer((_) async => latestVersion);

        final result = await commandRunner.run(['completion']);
        expect(result, equals(ExitCode.success.code));
        verifyNever(() => logger.info(updatePrompt));
      },
    );

    test('does not show update message when using update command', () async {
      when(
        () => pubUpdater.getLatestVersion(any()),
      ).thenAnswer((_) async => latestVersion);
      when(
        () => pubUpdater.update(
          packageName: packageName,
          versionConstraint: any(named: 'versionConstraint'),
        ),
      ).thenAnswer((_) async => processResult);
      when(
        () => pubUpdater.isUpToDate(
          packageName: any(named: 'packageName'),
          currentVersion: any(named: 'currentVersion'),
        ),
      ).thenAnswer((_) async => true);

      final progress = _MockProgress();
      final progressLogs = <String>[];
      when(() => progress.complete(any())).thenAnswer((_) {
        final message = _.positionalArguments.elementAt(0) as String?;
        if (message != null) progressLogs.add(message);
      });
      when(() => logger.progress(any())).thenReturn(progress);

      final result = await commandRunner.run(['update']);
      expect(result, equals(ExitCode.success.code));
      verifyNever(() => logger.info(updatePrompt));
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
      test('outputs current version', () async {
        final result = await commandRunner.run(['--version']);
        expect(result, equals(ExitCode.success.code));
        verify(() => logger.info(packageVersion)).called(1);
      });
    });

    group('--verbose', () {
      test('enables verbose logging', () async {
        final result = await commandRunner.run(['--verbose']);
        expect(result, equals(ExitCode.success.code));
      });
    });
  });
}

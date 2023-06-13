import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_cli/src/logger.dart' hide logger;
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/upgrader.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockProcess extends Mock implements Process {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockUpgrader extends Mock implements Upgrader {}

void main() {
  group(ShorebirdCliCommandRunner, () {
    late ArgResults argResults;
    late Logger logger;
    late Progress progress;
    late ShorebirdProcess shorebirdProcess;
    late Process process;
    late Upgrader upgrader;
    late ShorebirdProcessResult processResult;
    late ShorebirdCliCommandRunner commandRunner;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          processRef.overrideWith(() => shorebirdProcess),
          upgraderRef.overrideWith(() => upgrader),
        },
      );
    }

    setUp(() {
      argResults = _MockArgResults();
      logger = _MockLogger();
      progress = _MockProgress();
      shorebirdProcess = _MockShorebirdProcess();
      process = _MockProcess();
      upgrader = _MockUpgrader();
      ShorebirdEnvironment.shorebirdEngineRevision = 'test-revision';
      processResult = _MockProcessResult();
      when(
        () => shorebirdProcess.start(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => process);
      when(() => process.stdout).thenAnswer((_) => const Stream.empty());
      when(() => process.stderr).thenAnswer((_) => const Stream.empty());
      when(() => process.stdin).thenAnswer((_) => IOSink(StreamController()));
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      when(() => upgrader.isUpToDate()).thenAnswer((_) async => true);
      when(() => logger.progress(any())).thenReturn(progress);
      commandRunner = runWithOverrides(ShorebirdCliCommandRunner.new);
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

    test('handles UsageException', () async {
      final exception = UsageException('oops!', 'exception usage');
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
      verify(() => logger.info('exception usage')).called(1);
    });

    group('--version', () {
      test('outputs current version and engine revisions', () async {
        final result = await runWithOverrides(
          () => commandRunner.run(['--version']),
        );
        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info(
            '''
Shorebird $packageVersion
Shorebird Engine • revision ${ShorebirdEnvironment.shorebirdEngineRevision}''',
          ),
        ).called(1);
      });
    });

    group('updates', () {
      test('checks for updates', () async {
        await runWithOverrides(
          () => commandRunner.run(['--verbose']),
        );
        verify(() => upgrader.isUpToDate()).called(1);
      });

      test('gracefully handles updates check failures', () async {
        when(() => upgrader.isUpToDate()).thenThrow(Exception('oops'));
        final result = await runWithOverrides(
          () => commandRunner.run(['--verbose']),
        );
        expect(result, equals(ExitCode.success.code));
        verify(() => upgrader.isUpToDate()).called(1);
      });

      test('attempts to upgrade when out of date', () async {
        final exception = Exception('oops');
        when(() => upgrader.isUpToDate()).thenAnswer((_) async => false);
        when(() => upgrader.upgrade()).thenThrow(exception);
        final result = await runWithOverrides(
          () => commandRunner.run(['--verbose']),
        );
        expect(result, equals(ExitCode.success.code));
        verify(() => upgrader.isUpToDate()).called(1);
        verify(() => upgrader.upgrade()).called(1);
      });

      test('successfully upgrades when out of date', () async {
        when(() => argResults['version']).thenReturn(true);
        when(() => argResults.arguments).thenReturn(['--version']);
        when(() => upgrader.isUpToDate()).thenAnswer((_) async => false);
        when(() => upgrader.upgrade()).thenAnswer((_) async {});
        final result = await runWithOverrides(
          () => commandRunner.runCommand(argResults),
        );
        expect(result, equals(ExitCode.success.code));
        verify(() => upgrader.isUpToDate()).called(1);
        verify(() => upgrader.upgrade()).called(1);
        verify(
          () => shorebirdProcess.start(
            'dart',
            any(that: contains('--version')),
            runInShell: true,
          ),
        ).called(1);
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

    group('completion', () {
      test('fast tracks completion', () async {
        final result = await runWithOverrides(
          () => commandRunner.run(['completion']),
        );
        expect(result, equals(ExitCode.success.code));
      });
    });
  });
}

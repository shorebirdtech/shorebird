import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_cli/src/logger.dart' hide logger;
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

void main() {
  group('ShorebirdCliCommandRunner', () {
    late Logger logger;
    late ShorebirdProcessResult processResult;
    late ShorebirdCliCommandRunner commandRunner;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(body, values: {loggerRef.overrideWith(() => logger)});
    }

    ShorebirdCliCommandRunner buildRunner() {
      return runScoped(
        ShorebirdCliCommandRunner.new,
        values: {loggerRef.overrideWith(() => logger)},
      );
    }

    setUp(() {
      logger = _MockLogger();
      ShorebirdEnvironment.shorebirdEngineRevision = 'test-revision';
      processResult = _MockProcessResult();
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      commandRunner = buildRunner();
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

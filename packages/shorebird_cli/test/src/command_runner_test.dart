import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockProcessWrapper extends Mock implements ProcessWrapper {}

void main() {
  group('ShorebirdCliCommandRunner', () {
    late Logger logger;
    late ShorebirdProcessResult processResult;
    late ProcessWrapper processWrapper;
    late ShorebirdCliCommandRunner commandRunner;

    setUp(() {
      logger = _MockLogger();

      ShorebirdEnvironment.shorebirdEngineRevision = 'test-revision';
      processResult = _MockProcessResult();
      processWrapper = _MockProcessWrapper();
      // when(
      //   () => processWrapper.run(
      //     any(),
      //     any(),
      //     runInShell: any(named: 'runInShell'),
      //     environment: any(named: 'environment'),
      //     workingDirectory: any(named: 'workingDirectory'),
      //   ),
      // ).thenAnswer((_) async => processResult);

      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      commandRunner = ShorebirdCliCommandRunner(
        logger: logger,
        processWrapper: processWrapper,
      );
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
Shorebird Channel • null
Shorebird Engine • revision ${ShorebirdEnvironment.shorebirdEngineRevision}
flutterVersionString''',
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

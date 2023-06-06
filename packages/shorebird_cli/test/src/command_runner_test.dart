import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/command_runner.dart';
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

    setUp(() {
      logger = _MockLogger();

      ShorebirdEnvironment.shorebirdEngineRevision = 'test-revision';
      processResult = _MockProcessResult();
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      commandRunner = ShorebirdCliCommandRunner(logger: logger);
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
        final versionResult = await Process.run('flutter', ['--version']);
        final versionString = versionResult.stdout.toString().trim();
        final flutterVersion = versionString
            .split('\n')
            .firstWhereOrNull((element) => element.startsWith('Flutter'))!
            .split('•')
            .first;
        final result = await commandRunner.run(['--version']);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info(
            '''
Shorebird $packageVersion
Shorebird Engine • revision ${ShorebirdEnvironment.shorebirdEngineRevision}
Tools • $flutterVersion''',
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

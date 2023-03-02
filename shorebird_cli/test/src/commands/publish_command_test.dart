import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  group('publish', () {
    late Logger logger;
    late ShorebirdCliCommandRunner commandRunner;

    setUp(() {
      logger = _MockLogger();
      commandRunner = ShorebirdCliCommandRunner(logger: logger);
    });

    test('outputs coming soon...', () async {
      final exitCode = await commandRunner.run(['publish']);

      expect(exitCode, ExitCode.success.code);

      verify(() => logger.info('Coming soon...')).called(1);
    });
  });
}

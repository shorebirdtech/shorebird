import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/cache/cache_command.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  group('cache', () {
    late Logger logger;
    late CacheCommand command;

    setUp(() {
      logger = _MockLogger();
      command = CacheCommand(logger: logger);
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });
  });
}

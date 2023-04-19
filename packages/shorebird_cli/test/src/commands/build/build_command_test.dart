import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  group('build', () {
    late Logger logger;
    late BuildCommand command;

    setUp(() {
      logger = _MockLogger();
      command = BuildCommand(logger: logger);
    });

    test('has a description', () async {
      expect(command.description, isNotEmpty);
    });
  });
}

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:test/test.dart';

void main() {
  group(ShorebirdCommand, () {
    test('passes logger to auth in default builder', () {
      final logger = Logger();
      final command = TestCommand(logger: logger);
      expect(command.auth.logger, logger);
    });
  });
}

class TestCommand extends ShorebirdCommand {
  TestCommand({required super.logger});

  @override
  String get description => 'A test command';

  @override
  String get name => 'test';
}

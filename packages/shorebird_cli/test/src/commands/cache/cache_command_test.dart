import 'package:shorebird_cli/src/commands/cache/cache_command.dart';
import 'package:test/test.dart';

void main() {
  group('cache', () {
    late CacheCommand command;

    setUp(() {
      command = CacheCommand();
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });
  });
}

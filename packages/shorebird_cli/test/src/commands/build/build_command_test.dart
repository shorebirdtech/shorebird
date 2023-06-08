import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:test/test.dart';

void main() {
  group('build', () {
    late BuildCommand command;

    setUp(() {
      command = BuildCommand();
    });

    test('has a description', () async {
      expect(command.description, isNotEmpty);
    });
  });
}

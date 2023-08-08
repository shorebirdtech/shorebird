import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:test/test.dart';

void main() {
  group(FlutterVersionsCommand, () {
    test('has correct name and description', () {
      final command = FlutterVersionsCommand();
      expect(command.name, equals('versions'));
      expect(
        command.description,
        equals('Manage your Shorebird Flutter versions.'),
      );
    });
  });
}

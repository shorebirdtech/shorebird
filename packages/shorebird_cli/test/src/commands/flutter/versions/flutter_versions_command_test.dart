import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:test/test.dart';
import '../../../helpers.dart';

void main() {
  useTempWorkingDirectory();
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

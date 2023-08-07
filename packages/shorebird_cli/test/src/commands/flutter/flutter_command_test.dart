import 'package:shorebird_cli/src/commands/flutter/flutter_command.dart';
import 'package:test/test.dart';

void main() {
  group(FlutterCommand, () {
    test('has correct name and description', () {
      final command = FlutterCommand();
      expect(command.name, equals('flutter'));
      expect(
        command.description,
        equals('Manage your Shorebird Flutter installation.'),
      );
    });
  });
}

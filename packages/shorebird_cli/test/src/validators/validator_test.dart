import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';
import '../helpers.dart';

void main() {
  useTempWorkingDirectory();
  group(Validator, () {
    test('canRunInContext is true by default', () {
      expect(FakeValidator().canRunInCurrentContext(), equals(true));
    });

    test('incorrectContextMessage is null by default', () {
      expect(FakeValidator().incorrectContextMessage, isNull);
    });
  });
}

class FakeValidator extends Validator {
  @override
  String get description => 'A fake validator for testing';

  @override
  Future<List<ValidationIssue>> validate() async {
    return [];
  }
}

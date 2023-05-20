import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/run_command.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/shorebird_yaml_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockRunCommand extends Mock implements RunCommand {}

void main() {
  group('ShorebirdYamlValidator', () {
    late ShorebirdYamlValidator validator;
    late RunCommand command;
    late ShorebirdProcess shorebirdProcess;

    setUp(() {
      shorebirdProcess = _MockShorebirdProcess();

      command = _MockRunCommand();

      validator = ShorebirdYamlValidator(
        hasShorebirdYaml: () => command.hasShorebirdYaml,
      );
    });
    test('return no issue when shorebird yaml is there', () async {
      when(() => command.hasShorebirdYaml).thenReturn(true);
      final results = await validator.validate(shorebirdProcess);
      expect(results, isEmpty);
    });

    test('return an error when shorebird yaml is not there', () async {
      when(() => command.hasShorebirdYaml).thenReturn(false);
      final results = await validator.validate(shorebirdProcess);
      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.error);
      expect(
        results.first.message,
        contains('Shorebird is not initialized.'),
      );
      expect(
        validator.description,
        contains('Shorebird is initialized'),
      );
    });
  });
}

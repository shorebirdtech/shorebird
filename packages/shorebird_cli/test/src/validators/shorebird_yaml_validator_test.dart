import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group('ShorebirdYamlValidator', () {
    late ShorebirdYamlValidator validator;
    late ShorebirdProcess shorebirdProcess;
    late Directory tempDir;

    setUp(() {
      shorebirdProcess = _MockShorebirdProcess();
      tempDir = Directory.systemTemp.createTempSync();

      validator = ShorebirdYamlValidator();
    });
    test('return no issue when shorebird yaml is there', () async {
      final shorebirdFilePath = p.join(tempDir.path, 'shorebird.yaml');
      File(shorebirdFilePath).createSync();
      final results = await IOOverrides.runZoned(
        () => validator.validate(shorebirdProcess),
        getCurrentDirectory: () => tempDir,
      );
      expect(results, isEmpty);
    });

    test('return an error when shorebird yaml is not there', () async {
      final results = await IOOverrides.runZoned(
        () => validator.validate(shorebirdProcess),
        getCurrentDirectory: () => tempDir,
      );
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

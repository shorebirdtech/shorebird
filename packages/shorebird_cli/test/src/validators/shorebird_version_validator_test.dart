import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group(ShorebirdVersionValidator, () {
    late ShorebirdVersionValidator validator;
    late ShorebirdProcess shorebirdProcess;

    setUp(() {
      shorebirdProcess = _MockShorebirdProcess();
      validator = ShorebirdVersionValidator(
        isShorebirdVersionCurrent: () async => true,
      );
    });

    test('returns no issues when shorebird is up-to-date', () async {
      final results = await validator.validate(shorebirdProcess);
      expect(results, isEmpty);
    });

    test('returns a warning when a newer shorebird is available', () async {
      validator = ShorebirdVersionValidator(
        isShorebirdVersionCurrent: () async => false,
      );
      final results = await validator.validate(shorebirdProcess);
      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.warning);
      expect(
        results.first.message,
        contains('A new version of shorebird is available!'),
      );
    });

    test(
      'returns an error on failure to retrieve shorebird version',
      () async {
        validator = ShorebirdVersionValidator(
          isShorebirdVersionCurrent: () async {
            throw const ProcessException('', [], 'Some error');
          },
        );
        final results = await validator.validate(shorebirdProcess);

        expect(results, hasLength(1));
        expect(results.first.severity, ValidationIssueSeverity.error);
        expect(
          results.first.message,
          'Failed to get shorebird version. Error: Some error',
        );
      },
    );
  });
}

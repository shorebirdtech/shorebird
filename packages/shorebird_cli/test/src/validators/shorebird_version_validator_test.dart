import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockShorebirdVersion extends Mock implements ShorebirdVersion {}

void main() {
  group('ShorebirdVersionValidator', () {
    late ShorebirdVersion shorebirdVersion;
    late ShorebirdVersionValidator validator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          shorebirdVersionRef.overrideWith(() => shorebirdVersion),
        },
      );
    }

    setUp(() {
      shorebirdVersion = _MockShorebirdVersion();
      validator = ShorebirdVersionValidator();

      when(
        shorebirdVersion.isLatest,
      ).thenAnswer((_) async => false);
    });

    test('has a non-empty description', () {
      expect(validator.description, isNotEmpty);
    });

    test('canRunInContext always returns true', () {
      expect(validator.canRunInCurrentContext(), isTrue);
    });

    test('returns no issues when shorebird is up-to-date', () async {
      when(shorebirdVersion.isLatest).thenAnswer((_) async => true);

      final results = await runWithOverrides(validator.validate);

      expect(results, isEmpty);
    });

    test('retursn an error when shorebird version cannot be determined',
        () async {
      when(shorebirdVersion.isLatest).thenThrow(
        const ProcessException('git', ['rev-parse', 'HEAD']),
      );

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.error);
      expect(
        results.first.message,
        contains('Failed to get shorebird version'),
      );
    });

    test('returns a warning when a newer shorebird is available', () async {
      when(shorebirdVersion.isLatest).thenAnswer((_) async => false);

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.warning);
      expect(
        results.first.message,
        contains('A new version of shorebird is available!'),
      );
    });
  });
}

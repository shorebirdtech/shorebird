import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/shorebird_version_manager.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockShorebirdVersionManager extends Mock
    implements ShorebirdVersionManager {}

void main() {
  group('ShorebirdVersionValidator', () {
    late ShorebirdVersionManager shorebirdVersionManager;
    late ShorebirdVersionValidator validator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          shorebirdVersionManagerRef
              .overrideWith(() => shorebirdVersionManager),
        },
      );
    }

    setUp(() {
      shorebirdVersionManager = _MockShorebirdVersionManager();

      validator = ShorebirdVersionValidator();

      when(
        shorebirdVersionManager.isShorebirdVersionCurrent,
      ).thenAnswer((_) async => false);
    });

    test('has a non-empty description', () {
      expect(validator.description, isNotEmpty);
    });

    test('is not project-specific', () {
      expect(validator.scope, ValidatorScope.installation);
    });

    test('returns no issues when shorebird is up-to-date', () async {
      when(shorebirdVersionManager.isShorebirdVersionCurrent)
          .thenAnswer((_) async => true);

      final results = await runWithOverrides(validator.validate);
      expect(results, isEmpty);
    });

    test('returns a warning when a newer shorebird is available', () async {
      when(shorebirdVersionManager.isShorebirdVersionCurrent)
          .thenAnswer((_) async => false);

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

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(ShorebirdFlutterVersionSupportsIOSValidator, () {
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdFlutterVersionSupportsIOSValidator validator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    setUp(() {
      shorebirdFlutter = MockShorebirdFlutter();
      validator = ShorebirdFlutterVersionSupportsIOSValidator();
    });

    test('has a non-empty description', () {
      expect(validator.description, isNotEmpty);
    });

    group('when flutter version lookup fails', () {
      setUp(() {
        when(() => shorebirdFlutter.getVersion()).thenAnswer((_) async => null);
      });

      test('returns validation warning', () async {
        final results = await runWithOverrides(validator.validate);

        expect(
          results,
          equals([
            const ValidationIssue(
              severity: ValidationIssueSeverity.warning,
              message: 'Unable to determine Shorebird Flutter version',
            ),
          ]),
        );
      });
    });

    group('when flutter version is before the first bad version', () {
      setUp(() {
        when(
          () => shorebirdFlutter.getVersion(),
        ).thenAnswer((_) async => Version(3, 16, 3));
      });

      test('returns validation warning', () async {
        final results = await runWithOverrides(validator.validate);

        expect(
          results,
          equals(
            [
              ValidationIssue(
                severity: ValidationIssueSeverity.warning,
                message: '''
Shorebird iOS recommends Flutter 3.16.9 or later.
Run ${lightCyan.wrap('shorebird flutter versions use 3.16.9')} to upgrade.
''',
              ),
            ],
          ),
        );
      });

      group('when flutter version is in known bad range', () {
        setUp(() {
          when(
            () => shorebirdFlutter.getVersion(),
          ).thenAnswer((_) async => Version(3, 16, 7));
        });

        test('returns validation warning', () async {
          final results = await runWithOverrides(validator.validate);

          expect(
            results,
            equals(
              [
                ValidationIssue(
                  severity: ValidationIssueSeverity.error,
                  message: '''
Shorebird iOS does not support Flutter 3.16.7.
Run ${lightCyan.wrap('shorebird flutter versions use 3.16.9')} to upgrade.
''',
                ),
              ],
            ),
          );
        });
      });

      group('when flutter version is above the last bad flutter version', () {
        setUp(() {
          when(
            () => shorebirdFlutter.getVersion(),
          ).thenAnswer((_) async => Version(3, 16, 10));
        });

        test('returns no validation issues', () async {
          final results = await runWithOverrides(validator.validate);

          expect(results, isEmpty);
        });
      });
    });
  });
}

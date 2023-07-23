import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockValidator extends Mock implements Validator {}

void main() {
  group(Doctor, () {
    const validationWarning = ValidationIssue(
      severity: ValidationIssueSeverity.warning,
      message: 'warning',
    );
    const validationError = ValidationIssue(
      severity: ValidationIssueSeverity.error,
      message: 'error',
    );
    final fixableValidationWarning = ValidationIssue(
      severity: ValidationIssueSeverity.warning,
      message: 'warning',
      fix: () {},
    );

    late Logger logger;
    late Progress progress;
    late Validator projectScopeValidator;
    late Validator installationScopeValidator;
    late Validator noIssuesValidator;
    late Validator fixableWarningValidator;
    late Validator warningValidator;
    late Validator errorValidator;
    late Doctor doctor;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
        },
      );
    }

    setUp(() {
      logger = _MockLogger();
      progress = _MockProgress();
      noIssuesValidator = _MockValidator();
      fixableWarningValidator = _MockValidator();
      warningValidator = _MockValidator();
      errorValidator = _MockValidator();
      projectScopeValidator = _MockValidator();
      installationScopeValidator = _MockValidator();

      doctor = Doctor();

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.info(any())).thenReturn(null);

      when(projectScopeValidator.validate).thenAnswer((_) async => []);
      when(() => projectScopeValidator.scope)
          .thenReturn(ValidatorScope.project);

      when(installationScopeValidator.validate).thenAnswer((_) async => []);
      when(() => installationScopeValidator.scope)
          .thenReturn(ValidatorScope.installation);

      when(noIssuesValidator.validate).thenAnswer((_) async => []);
      when(() => noIssuesValidator.scope)
          .thenReturn(ValidatorScope.installation);

      when(fixableWarningValidator.validate).thenAnswer(
        (_) async => [fixableValidationWarning],
      );
      when(warningValidator.validate).thenAnswer(
        (_) async => [validationWarning],
      );
      when(errorValidator.validate).thenAnswer((_) async => [validationError]);
    });

    group('validate', () {
      test('prints messages when warnings or errors found', () async {
        await runWithOverrides(() => doctor.runValidators([]));

        for (final validator in doctor.allValidators) {
          verify(validator.validate).called(1);
        }

        verify(
          () =>
              logger.info(any(that: stringContainsInOrder(['[!]', 'oh no!']))),
        ).called(1);

        verify(
          () =>
              logger.info(any(that: stringContainsInOrder(['[✗]', 'OH NO!']))),
        ).called(1);

        verify(
          () => logger.info(any(that: contains('2 issues detected.'))),
        ).called(1);
      });

      test('does not run project validators if not in a project', () async {
        // TODO
      });

      test(
          '''does not tell the user we can fix issues if no fixable issues are found''',
          () async {
        await runWithOverrides(
          () => doctor.runValidators([warningValidator, errorValidator]),
        );

        verifyNever(
          () => logger.info(
            any(
              that: stringContainsInOrder([
                'can be fixed automatically with',
                'shorebird doctor --fix',
              ]),
            ),
          ),
        );
      });
    });
  });
}

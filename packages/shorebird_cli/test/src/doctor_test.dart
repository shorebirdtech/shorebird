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

    late Logger logger;
    late Progress progress;
    late Validator noIssuesValidator;
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
      warningValidator = _MockValidator();
      errorValidator = _MockValidator();

      doctor = Doctor();

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.info(any())).thenReturn(null);

      when(noIssuesValidator.validate).thenAnswer((_) async => []);
      when(noIssuesValidator.canRunInCurrentContext).thenReturn(true);
      when(() => noIssuesValidator.description)
          .thenReturn('no issues validator');

      when(warningValidator.validate).thenAnswer(
        (_) async => [validationWarning],
      );
      when(warningValidator.canRunInCurrentContext).thenReturn(true);
      when(() => warningValidator.description).thenReturn('warning validator');

      when(errorValidator.validate).thenAnswer((_) async => [validationError]);
      when(errorValidator.canRunInCurrentContext).thenReturn(true);
      when(() => errorValidator.description).thenReturn('error validator');
    });

    group('runValidators', () {
      test('prints messages when warnings and errors found', () async {
        final validators = [
          warningValidator,
          errorValidator,
        ];
        await runWithOverrides(() => doctor.runValidators(validators));

        for (final validator in validators) {
          verify(validator.validate).called(1);
        }

        verify(
          () =>
              logger.info(any(that: stringContainsInOrder(['[!]', 'warning']))),
        ).called(1);

        verify(
          () => logger.info(any(that: stringContainsInOrder(['[✗]', 'error']))),
        ).called(1);

        verify(
          () => logger.info(any(that: contains('2 issues detected.'))),
        ).called(1);
      });

      test('only runs validators that can run in the current context',
          () async {
        final validators = [
          noIssuesValidator,
          warningValidator,
          errorValidator,
        ];
        when(() => warningValidator.canRunInCurrentContext()).thenReturn(false);

        await runWithOverrides(() async => doctor.runValidators(validators));

        verify(noIssuesValidator.validate).called(1);
        verifyNever(warningValidator.validate);
        verify(errorValidator.validate).called(1);
      });

      test('tells the user when no issues are found', () async {
        final validators = [
          noIssuesValidator,
        ];

        await runWithOverrides(() async => doctor.runValidators(validators));

        verify(
          () => logger.info(any(that: contains('No issues detected!'))),
        ).called(1);
      });

      group('fix', () {
        var wasFixCalled = false;
        final fixableValidationWarning = ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: 'warning',
          fix: () => wasFixCalled = true,
        );
        final erroringValidationWarning = ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: 'warning',
          fix: () => throw Exception('oh no!'),
        );

        late Validator fixableWarningValidator;

        setUp(() {
          wasFixCalled = false;
          fixableWarningValidator = _MockValidator();

          when(fixableWarningValidator.validate).thenAnswer(
            (_) async => [fixableValidationWarning],
          );
          when(() => fixableWarningValidator.description)
              .thenReturn('fixable warning validator');
          when(fixableWarningValidator.canRunInCurrentContext).thenReturn(true);
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

        test('does not perform fixes if applyFixes is false', () async {
          await runWithOverrides(
            () => doctor.runValidators([fixableWarningValidator]),
          );

          verify(
            () => logger.info(
              any(
                that: stringContainsInOrder([
                  'can be fixed automatically with',
                  'shorebird doctor --fix',
                ]),
              ),
            ),
          ).called(1);
          expect(wasFixCalled, isFalse);
        });

        test('performs fixes if applyFixes is true', () async {
          when(fixableWarningValidator.validate).thenAnswer(
            (_) async => wasFixCalled ? [] : [fixableValidationWarning],
          );
          await runWithOverrides(
            () async => doctor.runValidators(
              [fixableWarningValidator],
              applyFixes: true,
            ),
          );

          verify(() => progress.update('Fixing'));
          verify(
            () => progress.complete(
              'fixable warning validator ${green.wrap('(1 fix applied)')}',
            ),
          ).called(1);
          expect(wasFixCalled, isTrue);
        });

        test('prints error if fixes fail to apply', () async {
          when(fixableWarningValidator.validate).thenAnswer(
            (_) async => [erroringValidationWarning],
          );
          await runWithOverrides(
            () async => doctor.runValidators(
              [fixableWarningValidator],
              applyFixes: true,
            ),
          );

          verify(
            () => logger.err(
              '''  An error occurred while attempting to fix warning: Exception: oh no!''',
            ),
          ).called(1);
        });
      });
    });
  });
}

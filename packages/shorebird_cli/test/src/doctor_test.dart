import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(Doctor, () {
    const validationWarning = ValidationIssue(
      severity: ValidationIssueSeverity.warning,
      message: '''
warning
with multiple lines''',
    );
    const validationError = ValidationIssue(
      severity: ValidationIssueSeverity.error,
      message: 'error',
    );

    late ShorebirdLogger logger;
    late Progress progress;
    late Validator noIssuesValidator;
    late Validator warningValidator;
    late Validator errorValidator;
    late Doctor doctor;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(body, values: {loggerRef.overrideWith(() => logger)});
    }

    setUp(() {
      logger = MockShorebirdLogger();
      progress = MockProgress();
      noIssuesValidator = MockValidator();
      warningValidator = MockValidator();
      errorValidator = MockValidator();

      doctor = Doctor();

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.info(any())).thenReturn(null);

      when(noIssuesValidator.validate).thenAnswer((_) async => []);
      when(noIssuesValidator.canRunInCurrentContext).thenReturn(true);
      when(
        () => noIssuesValidator.description,
      ).thenReturn('no issues validator');

      when(
        warningValidator.validate,
      ).thenAnswer((_) async => [validationWarning]);
      when(warningValidator.canRunInCurrentContext).thenReturn(true);
      when(() => warningValidator.description).thenReturn('warning validator');

      when(errorValidator.validate).thenAnswer((_) async => [validationError]);
      when(errorValidator.canRunInCurrentContext).thenReturn(true);
      when(() => errorValidator.description).thenReturn('error validator');
    });

    group('validate', () {
      test('returns what each runnable validator found, silently', () async {
        final skippedValidator = MockValidator();
        when(skippedValidator.canRunInCurrentContext).thenReturn(false);

        final results = await runWithOverrides(
          () => doctor.validate([
            noIssuesValidator,
            warningValidator,
            errorValidator,
            skippedValidator,
          ]),
        );

        expect(
          results.map((r) => r.name),
          equals([
            'no issues validator',
            'warning validator',
            'error validator',
          ]),
        );
        // Warnings don't fail a validator; errors do.
        expect(results.map((r) => r.ok), equals([true, true, false]));
        expect(
          results.last.toJson(),
          equals({
            'name': 'error validator',
            'ok': false,
            'issues': [
              {'severity': 'error', 'message': 'error'},
            ],
          }),
        );
        verifyNever(skippedValidator.validate);
        verifyZeroInteractions(logger);
      });
    });

    group('runValidators', () {
      test('prints messages when warnings and errors found', () async {
        final validators = [warningValidator, errorValidator];
        await runWithOverrides(() => doctor.runValidators(validators));

        for (final validator in validators) {
          verify(validator.validate).called(1);
        }

        verify(() => logger.info('  ${yellow.wrap('[!]')} warning')).called(1);
        verify(() => logger.info('      with multiple lines')).called(1);
        verify(() => logger.info('  ${red.wrap('[✗]')} error')).called(1);
        verify(() => logger.info('2 issues detected.')).called(1);
      });

      group('when validators only yield warnings', () {
        test('completes validator progress as success', () async {
          await runWithOverrides(
            () => doctor.runValidators([warningValidator]),
          );

          verify(() => progress.complete(any())).called(1);
          verifyNever(() => progress.fail(any()));
        });
      });

      group('when validators yield errors', () {
        test('completes validator progress as failure', () async {
          await runWithOverrides(() => doctor.runValidators([errorValidator]));

          verify(() => progress.fail(any())).called(1);
          verifyNever(() => progress.complete(any()));
        });
      });

      test(
        'only runs validators that can run in the current context',
        () async {
          final validators = [
            noIssuesValidator,
            warningValidator,
            errorValidator,
          ];
          when(
            () => warningValidator.canRunInCurrentContext(),
          ).thenReturn(false);

          await runWithOverrides(() async => doctor.runValidators(validators));

          verify(noIssuesValidator.validate).called(1);
          verifyNever(warningValidator.validate);
          verify(errorValidator.validate).called(1);
        },
      );

      test('tells the user when no issues are found', () async {
        final validators = [noIssuesValidator];

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
          fixableWarningValidator = MockValidator();

          when(
            fixableWarningValidator.validate,
          ).thenAnswer((_) async => [fixableValidationWarning]);
          when(
            () => fixableWarningValidator.description,
          ).thenReturn('fixable warning validator');
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
          },
        );

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
            () async => doctor.runValidators([
              fixableWarningValidator,
            ], applyFixes: true),
          );

          verify(() => progress.update('Fixing'));
          verify(
            () => progress.complete(
              'fixable warning validator ${green.wrap('(1 fix applied)')}',
            ),
          ).called(1);
          expect(wasFixCalled, isTrue);
        });

        test('counts only fixable issues as fixable', () async {
          when(fixableWarningValidator.validate).thenAnswer(
            (_) async => [fixableValidationWarning, validationError],
          );
          await runWithOverrides(
            () => doctor.runValidators([fixableWarningValidator]),
          );

          verify(() => logger.info('2 issues detected.')).called(1);
          verify(
            () => logger.info(
              any(
                that: stringContainsInOrder([
                  '1 issue can be fixed automatically with',
                  'shorebird doctor --fix',
                ]),
              ),
            ),
          ).called(1);
        });

        group('when a fix leaves other issues unresolved', () {
          setUp(() {
            when(fixableWarningValidator.validate).thenAnswer(
              (_) async => wasFixCalled
                  ? [validationError]
                  : [fixableValidationWarning, validationError],
            );
          });

          test('reports the remaining issues and the summary', () async {
            await runWithOverrides(
              () => doctor.runValidators([
                fixableWarningValidator,
                warningValidator,
              ], applyFixes: true),
            );

            expect(wasFixCalled, isTrue);
            verify(
              () => progress.fail(
                'fixable warning validator ${green.wrap('(1 fix applied)')}',
              ),
            ).called(1);
            // The fixed validator is reported once, as a failure, never also
            // as a completion. The only completion is the second,
            // warning-only validator's.
            verifyNever(
              () => progress.complete(
                'fixable warning validator ${green.wrap('(1 fix applied)')}',
              ),
            );
            verify(() => progress.complete(any())).called(1);
            verify(
              () => logger.info(
                '  ${validationError.displayMessage!}',
              ),
            ).called(1);
            verify(() => logger.info('2 issues detected.')).called(1);
          });
        });

        test('logs failed fixes even when another fix applied', () async {
          when(fixableWarningValidator.validate).thenAnswer(
            (_) async => wasFixCalled
                ? [erroringValidationWarning]
                : [fixableValidationWarning, erroringValidationWarning],
          );
          await runWithOverrides(
            () async => doctor.runValidators([
              fixableWarningValidator,
            ], applyFixes: true),
          );

          verify(
            () => logger.err(
              '''  An error occurred while attempting to fix warning: Exception: oh no!''',
            ),
          ).called(1);
          verify(() => logger.info('1 issue detected.')).called(1);
        });

        test('prints error if fixes fail to apply', () async {
          when(
            fixableWarningValidator.validate,
          ).thenAnswer((_) async => [erroringValidationWarning]);
          await runWithOverrides(
            () async => doctor.runValidators([
              fixableWarningValidator,
            ], applyFixes: true),
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

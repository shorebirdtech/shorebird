import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
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
      when(() => noIssuesValidator.scope)
          .thenReturn(ValidatorScope.installation);
      when(() => noIssuesValidator.description)
          .thenReturn('no issues validator');

      when(warningValidator.validate).thenAnswer(
        (_) async => [validationWarning],
      );
      when(() => warningValidator.scope)
          .thenReturn(ValidatorScope.installation);
      when(() => warningValidator.description).thenReturn('warning validator');

      when(errorValidator.validate).thenAnswer((_) async => [validationError]);
      when(() => errorValidator.scope).thenReturn(ValidatorScope.installation);
      when(() => errorValidator.description).thenReturn('error validator');
    });

    group('validate', () {
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

      group('validator scope', () {
        const appId = 'test-app-id';
        late Validator projectScopeValidator;
        late Validator installationScopeValidator;

        Directory setUpTempDir() {
          final tempDir = Directory.systemTemp.createTempSync();
          File(
            p.join(tempDir.path, 'shorebird.yaml'),
          ).writeAsStringSync('app_id: $appId');
          return tempDir;
        }

        setUp(() {
          projectScopeValidator = _MockValidator();
          installationScopeValidator = _MockValidator();

          when(projectScopeValidator.validate).thenAnswer((_) async => []);
          when(() => projectScopeValidator.scope)
              .thenReturn(ValidatorScope.project);
          when(() => projectScopeValidator.description)
              .thenReturn('project-scoped validator');

          when(installationScopeValidator.validate).thenAnswer((_) async => []);
          when(() => installationScopeValidator.scope)
              .thenReturn(ValidatorScope.installation);
          when(() => installationScopeValidator.description)
              .thenReturn('installation-scoped validator');
        });

        test('does not run project-scoped validators in project directory',
            () async {
          final validators = [
            projectScopeValidator,
            installationScopeValidator
          ];
          await runWithOverrides(
            () => doctor.runValidators(validators),
          );
          verify(installationScopeValidator.validate).called(1);
          verifyNever(projectScopeValidator.validate);
        });

        test('runs project-scoped validators in project directory', () async {
          final tempDir = setUpTempDir();
          final validators = [
            projectScopeValidator,
            installationScopeValidator
          ];
          await runWithOverrides(
            () async => IOOverrides.runZoned(
              () => doctor.runValidators(validators),
              getCurrentDirectory: () => tempDir,
            ),
          );
          verify(installationScopeValidator.validate).called(1);
          verify(projectScopeValidator.validate).called(1);
        });
      });

      group('fix', () {
        var wasFixCalled = false;
        final fixableValidationWarning = ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: 'warning',
          fix: () => wasFixCalled = true,
        );

        late Validator fixableWarningValidator;

        setUp(() {
          wasFixCalled = false;
          fixableWarningValidator = _MockValidator();

          when(fixableWarningValidator.validate).thenAnswer(
            (_) async => [fixableValidationWarning],
          );
          when(() => fixableWarningValidator.scope)
              .thenReturn(ValidatorScope.installation);
          when(() => fixableWarningValidator.description)
              .thenReturn('fixable warning validator');
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
      });
    });
  });
}

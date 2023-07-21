import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockShorebirdVersionValidator extends Mock
    implements ShorebirdVersionValidator {}

class _MockAndroidInternetPermissionValidator extends Mock
    implements AndroidInternetPermissionValidator {}

class _MockDoctor extends Mock implements Doctor {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group('doctor', () {
    const androidValidatorDescription = 'Android';
    const appId = 'test-app-id';

    late ArgResults argResults;
    late Doctor doctor;
    late Logger logger;
    late Progress progress;
    late DoctorCommand command;
    late AndroidInternetPermissionValidator androidInternetPermissionValidator;
    late ShorebirdVersionValidator shorebirdVersionValidator;
    late ShorebirdFlutterValidator shorebirdFlutterValidator;
    late ShorebirdProcess shorebirdProcess;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          doctorRef.overrideWith(() => doctor),
          loggerRef.overrideWith(() => logger),
          processRef.overrideWith(() => shorebirdProcess),
        },
      );
    }

    Directory setUpTempDir() {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('app_id: $appId');
      return tempDir;
    }

    setUp(() {
      argResults = _MockArgResults();
      doctor = _MockDoctor();
      logger = _MockLogger();
      progress = _MockProgress();

      ShorebirdEnvironment.shorebirdEngineRevision = 'test-revision';

      when(() => argResults['fix']).thenReturn(false);

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.info(any())).thenReturn(null);

      androidInternetPermissionValidator =
          _MockAndroidInternetPermissionValidator();
      shorebirdVersionValidator = _MockShorebirdVersionValidator();
      shorebirdFlutterValidator = _MockShorebirdFlutterValidator();
      shorebirdProcess = _MockShorebirdProcess();
      registerFallbackValue(shorebirdProcess);

      when(() => androidInternetPermissionValidator.description)
          .thenReturn(androidValidatorDescription);
      when(() => androidInternetPermissionValidator.scope)
          .thenReturn(ValidatorScope.project);
      when(androidInternetPermissionValidator.validate)
          .thenAnswer((_) async => []);

      when(() => shorebirdVersionValidator.description)
          .thenReturn('Shorebird Version');
      when(() => shorebirdVersionValidator.scope)
          .thenReturn(ValidatorScope.installation);
      when(shorebirdVersionValidator.validate).thenAnswer((_) async => []);

      when(() => shorebirdFlutterValidator.description)
          .thenReturn('Shorebird Flutter');
      when(() => shorebirdFlutterValidator.scope)
          .thenReturn(ValidatorScope.installation);
      when(shorebirdFlutterValidator.validate).thenAnswer((_) async => []);

      when(() => doctor.allValidators).thenReturn([
        androidInternetPermissionValidator,
        shorebirdVersionValidator,
        shorebirdFlutterValidator,
      ]);

      command = runWithOverrides(DoctorCommand.new)
        ..testArgResults = argResults;
    });

    test('prints "no issues" when everything is OK', () async {
      final tempDir = setUpTempDir();

      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      for (final validator in doctor.allValidators) {
        verify(validator.validate).called(1);
      }
      verify(
        () => logger.info(any(that: contains('No issues detected'))),
      ).called(1);
    });

    test('prints messages when warnings or errors found', () async {
      when(androidInternetPermissionValidator.validate).thenAnswer(
        (_) async => [
          const ValidationIssue(
            severity: ValidationIssueSeverity.warning,
            message: 'oh no!',
          ),
          const ValidationIssue(
            severity: ValidationIssueSeverity.error,
            message: 'OH NO!',
          ),
        ],
      );

      final tempDir = setUpTempDir();

      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      for (final validator in doctor.allValidators) {
        verify(validator.validate).called(1);
      }

      verify(
        () => logger.info(any(that: stringContainsInOrder(['[!]', 'oh no!']))),
      ).called(1);

      verify(
        () => logger.info(any(that: stringContainsInOrder(['[✗]', 'OH NO!']))),
      ).called(1);

      verify(
        () => logger.info(any(that: contains('2 issues detected.'))),
      ).called(1);
    });

    test(
        '''does not run project-specific validators if not in a project directory''',
        () async {
      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => Directory.systemTemp.createTempSync(),
      );

      verify(shorebirdFlutterValidator.validate).called(1);
      verify(shorebirdVersionValidator.validate).called(1);
      verifyNever(androidInternetPermissionValidator.validate);
    });

    group('fix', () {
      test('tells the user we can fix issues if we can', () async {
        when(androidInternetPermissionValidator.validate).thenAnswer(
          (_) async => [
            ValidationIssue(
              severity: ValidationIssueSeverity.warning,
              message: 'oh no!',
              fix: () async {},
            ),
          ],
        );
        final tempDir = setUpTempDir();

        await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );

        verify(
          () => logger.info(
            any(
              that: stringContainsInOrder([
                '1 issue can be fixed automatically',
                'shorebird doctor --fix',
              ]),
            ),
          ),
        ).called(1);
      });

      test('does not tell the user we can fix issues if we cannot', () async {
        when(androidInternetPermissionValidator.validate).thenAnswer(
          (_) async => [
            const ValidationIssue(
              severity: ValidationIssueSeverity.warning,
              message: 'oh no!',
            ),
          ],
        );
        final tempDir = setUpTempDir();

        await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );

        verifyNever(
          () => logger.info(
            any(
              that: stringContainsInOrder([
                'We can fix some of these issues',
                'shorebird doctor --fix',
              ]),
            ),
          ),
        );
      });

      test('does not fix issues if --fix flag is not provided', () async {
        when(() => argResults['fix']).thenReturn(false);

        var fixCalled = false;
        when(androidInternetPermissionValidator.validate).thenAnswer(
          (_) async => [
            ValidationIssue(
              severity: ValidationIssueSeverity.warning,
              message: 'oh no!',
              fix: () => fixCalled = true,
            ),
          ],
        );

        final tempDir = setUpTempDir();

        await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );

        expect(fixCalled, isFalse);
        verifyNever(() => progress.update('Fixing'));
        verify(() => progress.fail(androidValidatorDescription)).called(1);
        verify(androidInternetPermissionValidator.validate).called(1);
      });

      test('fixes issues if the --fix flag is provided', () async {
        when(() => argResults['fix']).thenReturn(true);

        var fixCalled = false;
        final issues = [
          ValidationIssue(
            severity: ValidationIssueSeverity.warning,
            message: 'oh no!',
            fix: () => fixCalled = true,
          ),
        ];
        when(androidInternetPermissionValidator.validate).thenAnswer(
          (_) async {
            if (issues.isEmpty) return [];
            return [issues.removeLast()];
          },
        );
        final tempDir = setUpTempDir();

        await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );

        expect(fixCalled, isTrue);
        verify(() => progress.update('Fixing')).called(1);
        verify(
          () => progress.complete(any(that: contains('1 fix applied'))),
        ).called(1);
        verify(androidInternetPermissionValidator.validate).called(2);
      });

      test('does not print "fixed" if fix fails', () async {
        when(() => argResults['fix']).thenReturn(true);

        var fixCalled = false;
        when(androidInternetPermissionValidator.validate).thenAnswer(
          (_) async => [
            ValidationIssue(
              severity: ValidationIssueSeverity.warning,
              message: 'oh no!',
              fix: () => fixCalled = true,
            ),
          ],
        );

        final tempDir = setUpTempDir();

        await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );

        expect(fixCalled, isTrue);
        verify(() => progress.update('Fixing')).called(1);
        verify(() => progress.fail(androidValidatorDescription)).called(1);
        verifyNever(
          () => progress.complete(any(that: contains('fix applied'))),
        );
        verifyNever(
          () => progress.complete(any(that: contains('fixes applied'))),
        );
        verify(androidInternetPermissionValidator.validate).called(2);
      });

      test('prints error and continues if fix() throws', () async {
        when(() => argResults['fix']).thenReturn(true);
        when(androidInternetPermissionValidator.validate).thenAnswer(
          (_) async => [
            ValidationIssue(
              severity: ValidationIssueSeverity.warning,
              message: 'oh no!',
              fix: () => throw Exception('oh no!'),
            ),
          ],
        );

        final tempDir = setUpTempDir();

        await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );

        verify(() => progress.update('Fixing')).called(1);
        verify(androidInternetPermissionValidator.validate).called(2);
        verify(
          () => logger.err(
            any(
              that: stringContainsInOrder([
                'An error occurred while attempting to fix',
                'oh no!',
              ]),
            ),
          ),
        ).called(1);
      });
    });
  });
}

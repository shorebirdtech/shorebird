import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockShorebirdVersionValidator extends Mock
    implements ShorebirdVersionValidator {}

class _MockAndroidInternetPermissionValidator extends Mock
    implements AndroidInternetPermissionValidator {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group('doctor', () {
    late ArgResults argResults;
    late Logger logger;
    late Progress progress;
    late DoctorCommand command;
    late AndroidInternetPermissionValidator androidInternetPermissionValidator;
    late ShorebirdVersionValidator shorebirdVersionValidator;
    late ShorebirdFlutterValidator shorebirdFlutterValidator;
    late ShorebirdProcess shorebirdProcess;

    setUp(() {
      argResults = _MockArgResults();
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

      when(() => androidInternetPermissionValidator.id)
          .thenReturn('$AndroidInternetPermissionValidator');
      when(() => androidInternetPermissionValidator.description)
          .thenReturn('Android');
      when(() => androidInternetPermissionValidator.validate(any()))
          .thenAnswer((_) async => []);

      when(() => shorebirdVersionValidator.id)
          .thenReturn('$ShorebirdVersionValidator');
      when(() => shorebirdVersionValidator.description)
          .thenReturn('Shorebird Version');
      when(() => shorebirdVersionValidator.validate(any()))
          .thenAnswer((_) async => []);

      when(() => shorebirdFlutterValidator.id)
          .thenReturn('$ShorebirdFlutterValidator');
      when(() => shorebirdFlutterValidator.description)
          .thenReturn('Shorebird Flutter');
      when(() => shorebirdFlutterValidator.validate(any()))
          .thenAnswer((_) async => []);

      command = DoctorCommand(
        logger: logger,
        validators: [
          androidInternetPermissionValidator,
          shorebirdVersionValidator,
          shorebirdFlutterValidator,
        ],
      )
        ..testArgResults = argResults
        ..testProcess = shorebirdProcess
        ..testEngineConfig = const EngineConfig.empty();
    });

    test('prints "no issues" when everything is OK', () async {
      await command.run();
      for (final validator in command.validators) {
        verify(() => validator.validate(shorebirdProcess)).called(1);
      }
      verify(
        () => logger.info(any(that: contains('No issues detected'))),
      ).called(1);
    });

    test('prints messages when warnings or errors found', () async {
      when(
        () => androidInternetPermissionValidator.validate(any()),
      ).thenAnswer(
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

      await command.run();

      for (final validator in command.validators) {
        verify(() => validator.validate(any())).called(1);
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

    test('tells the user we can fix issues if we can', () async {
      when(
        () => androidInternetPermissionValidator.validate(any()),
      ).thenAnswer(
        (_) async => [
          ValidationIssue(
            severity: ValidationIssueSeverity.warning,
            message: 'oh no!',
            fix: () async {},
          ),
        ],
      );

      await command.run();

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
      when(
        () => androidInternetPermissionValidator.validate(any()),
      ).thenAnswer(
        (_) async => [
          const ValidationIssue(
            severity: ValidationIssueSeverity.warning,
            message: 'oh no!',
          ),
        ],
      );

      await command.run();

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
      when(
        () => androidInternetPermissionValidator.validate(any()),
      ).thenAnswer(
        (_) async => [
          ValidationIssue(
            severity: ValidationIssueSeverity.warning,
            message: 'oh no!',
            fix: () async => fixCalled = true,
          ),
        ],
      );

      await command.run();

      expect(fixCalled, isFalse);
      verifyNever(() => progress.update('Fixing'));
      verify(() => progress.fail()).called(1);
      verify(
        () => androidInternetPermissionValidator.validate(any()),
      ).called(1);
    });

    test('fixes issues if the --fix flag is provided', () async {
      when(() => argResults['fix']).thenReturn(true);

      var fixCalled = false;
      final issues = [
        ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: 'oh no!',
          fix: () async => fixCalled = true,
        ),
      ];
      when(
        () => androidInternetPermissionValidator.validate(any()),
      ).thenAnswer(
        (_) async {
          if (issues.isEmpty) return [];
          return [issues.removeLast()];
        },
      );

      await command.run();

      expect(fixCalled, isTrue);
      verify(() => progress.update('Fixing')).called(1);
      verify(
        () => progress.complete(any(that: contains('1 fix applied'))),
      ).called(1);
      verify(
        () => androidInternetPermissionValidator.validate(any()),
      ).called(2);
    });

    test('does not print "fixed" if fix fails', () async {
      when(() => argResults['fix']).thenReturn(true);

      var fixCalled = false;
      when(
        () => androidInternetPermissionValidator.validate(any()),
      ).thenAnswer(
        (_) async => [
          ValidationIssue(
            severity: ValidationIssueSeverity.warning,
            message: 'oh no!',
            fix: () async => fixCalled = true,
          ),
        ],
      );

      await command.run();

      expect(fixCalled, isTrue);
      verify(() => progress.update('Fixing')).called(1);
      verifyNever(
        () => progress.complete(any(that: contains('fix applied'))),
      );
      verifyNever(
        () => progress.complete(any(that: contains('fixes applied'))),
      );
      verify(() => progress.fail()).called(1);
      verify(
        () => androidInternetPermissionValidator.validate(any()),
      ).called(2);
    });
  });
}

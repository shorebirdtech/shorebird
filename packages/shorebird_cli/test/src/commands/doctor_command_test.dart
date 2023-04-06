import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockShorebirdVersionValidator extends Mock
    implements ShorebirdVersionValidator {}

class _MockAndroidInternetPermissionValidator extends Mock
    implements AndroidInternetPermissionValidator {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

void main() {
  group('doctor', () {
    late Logger logger;
    late Progress progress;
    late DoctorCommand command;
    late AndroidInternetPermissionValidator androidInternetPermissionValidator;
    late ShorebirdVersionValidator shorebirdVersionValidator;

    setUp(() {
      logger = _MockLogger();
      progress = _MockProgress();

      androidInternetPermissionValidator =
          _MockAndroidInternetPermissionValidator();
      shorebirdVersionValidator = _MockShorebirdVersionValidator();

      command = DoctorCommand(
        logger: logger,
        validators: [
          androidInternetPermissionValidator,
          shorebirdVersionValidator,
        ],
      );

      when(() => logger.progress(any())).thenReturn(progress);

      when(() => logger.info(any())).thenReturn(null);

      when(() => androidInternetPermissionValidator.description)
          .thenReturn('Android');
      when(() => androidInternetPermissionValidator.validate())
          .thenAnswer((_) async => []);

      when(() => shorebirdVersionValidator.description)
          .thenReturn('Shorebird Version');
      when(() => shorebirdVersionValidator.validate())
          .thenAnswer((_) async => []);
    });

    test('prints "no issues" when everything is OK', () async {
      await command.run();
      for (final validator in command.validators) {
        verify(validator.validate).called(1);
      }
      verify(
        () => logger.info(any(that: contains('No issues detected'))),
      ).called(1);
    });

    test('prints messages when warnings or errors found', () async {
      when(
        () => androidInternetPermissionValidator.validate(),
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
        verify(validator.validate).called(1);
      }

      verify(
        () => logger.info(any(that: contains('${yellow.wrap('[!]')} oh no!'))),
      ).called(1);

      verify(
        () => logger.info(any(that: contains('${red.wrap('[✗]')} OH NO!'))),
      ).called(1);

      verify(
        () => logger.info(any(that: contains('2 issues detected.'))),
      ).called(1);
    });
  });
}

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

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
    late Logger logger;
    late Progress progress;
    late DoctorCommand command;
    late AndroidInternetPermissionValidator androidInternetPermissionValidator;
    late ShorebirdVersionValidator shorebirdVersionValidator;
    late ShorebirdFlutterValidator shorebirdFlutterValidator;
    late ShorebirdProcess shorebirdProcess;

    setUp(() {
      logger = _MockLogger();
      progress = _MockProgress();

      ShorebirdEnvironment.shorebirdEngineRevision = 'test-revision';

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

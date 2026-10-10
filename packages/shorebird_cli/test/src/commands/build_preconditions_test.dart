import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/build_preconditions.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../matchers.dart';
import '../mocks.dart';

void main() {
  late ShorebirdEnv shorebirdEnv;
  late ShorebirdLogger logger;
  late ShorebirdValidator shorebirdValidator;
  late Validator validator;

  R runWithOverrides<R>(R Function() body) {
    return runScoped(
      body,
      values: {
        loggerRef.overrideWith(() => logger),
        shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
      },
    );
  }

  setUp(() {
    shorebirdEnv = MockShorebirdEnv();
    logger = MockShorebirdLogger();
    shorebirdValidator = MockShorebirdValidator();
    validator = MockValidator();
  });

  group('assertBuildPreconditions', () {
    void stubValidatePreconditions({PreconditionFailedException? throws}) {
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
          supportedOperatingSystems: any(named: 'supportedOperatingSystems'),
        ),
      ).thenAnswer((_) async {
        if (throws != null) throw throws;
      });
    }

    test('checks auth, init, validators and OS', () async {
      stubValidatePreconditions();

      await expectLater(
        runWithOverrides(
          () => assertBuildPreconditions(
            validators: [validator],
            supportedOperatingSystems: {NativePlatform.linux},
          ),
        ),
        completes,
      );

      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
          checkShorebirdInitialized: true,
          validators: [validator],
          supportedOperatingSystems: {NativePlatform.linux},
        ),
      ).called(1);
    });

    test('exits with the failing precondition exit code', () async {
      final exception = ValidationFailedException();
      stubValidatePreconditions(throws: exception);

      await expectLater(
        () => runWithOverrides(assertBuildPreconditions),
        exitsWithCode(exception.exitCode),
      );
    });
  });

  group('assertAndroidPackageNameConfigured', () {
    test('returns normally when androidPackage is set', () {
      when(() => shorebirdEnv.androidPackageName).thenReturn('com.example');

      expect(
        () => runWithOverrides(assertAndroidPackageNameConfigured),
        returnsNormally,
      );
    });

    test('logs error and exits with config code when missing', () {
      when(() => shorebirdEnv.androidPackageName).thenReturn(null);

      expect(
        () => runWithOverrides(assertAndroidPackageNameConfigured),
        exitsWithCode(ExitCode.config),
      );
      verify(
        () => logger.err('Could not find androidPackage in pubspec.yaml.'),
      ).called(1);
    });
  });
}

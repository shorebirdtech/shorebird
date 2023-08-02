import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockPlatform extends Mock implements Platform {}

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

class _MockValidator extends Mock implements Validator {}

void main() {
  group(ShorebirdValidator, () {
    late Auth auth;
    late Logger logger;
    late Platform platform;
    late Validator validator;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          authRef.overrideWith(() => auth),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      auth = _MockAuth();
      logger = _MockLogger();
      platform = _MockPlatform();
      shorebirdEnv = _MockShorebirdEnv();
      validator = _MockValidator();
      shorebirdValidator = runWithOverrides(ShorebirdValidator.new);
    });

    group('PreconditionFailedException', () {
      test('have correct exit codes', () {
        expect(ShorebirdNotInitializedException().exitCode, ExitCode.config);
        expect(UserNotAuthorizedException().exitCode, ExitCode.noUser);
        expect(ValidationFailedException().exitCode, ExitCode.config);
        expect(
          UnsupportedOperatingSystemException().exitCode,
          ExitCode.unavailable,
        );
      });
    });

    group('validatePreconditions', () {
      test(
          'throws UnsupportedOperatingSystemException '
          'when the operating system is not supported', () async {
        when(() => platform.operatingSystem).thenReturn(Platform.linux);
        const supportedOperatingSystems = {Platform.macOS, Platform.windows};
        await expectLater(
          runWithOverrides(
            () => shorebirdValidator.validatePreconditions(
              supportedOperatingSystems: supportedOperatingSystems,
            ),
          ),
          throwsA(isA<UnsupportedOperatingSystemException>()),
        );
        verify(
          () => logger.err(
            '''This command is only supported on ${supportedOperatingSystems.join(' ,')}.''',
          ),
        ).called(1);
      });

      test(
          'throws UserNotAuthorizedException '
          'when user is not authenticated', () async {
        when(() => auth.isAuthenticated).thenReturn(false);
        await expectLater(
          runWithOverrides(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: true,
            ),
          ),
          throwsA(isA<UserNotAuthorizedException>()),
        );
        verifyInOrder([
          () => logger.err('You must be logged in to run this command.'),
          () => logger.info(
                '''If you already have an account, run ${lightCyan.wrap('shorebird login')} to sign in.''',
              ),
          () => logger.info(
                '''If you don't have a Shorebird account, run ${lightCyan.wrap('shorebird account create')} to create one.''',
              ),
        ]);
      });

      test(
          'throws ShorebirdNotInitializedException '
          'when shorebird has not been initialized', () async {
        when(() => shorebirdEnv.isShorebirdInitialized).thenReturn(false);
        await expectLater(
          runWithOverrides(
            () => shorebirdValidator.validatePreconditions(
              checkShorebirdInitialized: true,
            ),
          ),
          throwsA(isA<ShorebirdNotInitializedException>()),
        );
        verify(
          () => logger.err(
            'Shorebird is not initialized. Did you run "shorebird init"?',
          ),
        ).called(1);
      });

      test('throws ValidationFailedException if validator fails', () async {
        final issue = ValidationIssue(
          message: 'test issue',
          severity: ValidationIssueSeverity.error,
          fix: () async {},
        );
        when(() => validator.canRunInCurrentContext()).thenReturn(true);
        when(() => validator.validate()).thenAnswer((_) async => [issue]);
        await expectLater(
          runWithOverrides(
            () => shorebirdValidator.validatePreconditions(
              validators: [validator],
            ),
          ),
          throwsA(isA<ValidationFailedException>()),
        );
        verify(() => validator.validate()).called(1);
        verify(
          () => logger.err('Aborting due to validation errors.'),
        ).called(1);
        verify(() => logger.info('${red.wrap('[✗]')} ${issue.message}'))
            .called(1);
        verify(
          () => logger.info(
            '''1 issue can be fixed automatically with ${lightCyan.wrap('shorebird doctor --fix')}.''',
          ),
        ).called(1);
      });
    });
  });
}

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

import 'mocks.dart';

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
      auth = MockAuth();
      logger = MockLogger();
      platform = MockPlatform();
      shorebirdEnv = MockShorebirdEnv();
      validator = MockValidator();
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
                '''If you don't have a Shorebird account, go to ${link(uri: Uri.parse('https://console.shorebird.dev'))} to create one.''',
              ),
        ]);
      });

      group(
          'when shorebird has not been properly initialized for the current app',
          () {
        group("when shorebird.yaml doesn't exist", () {
          setUp(() {
            when(() => shorebirdEnv.hasShorebirdYaml).thenReturn(false);
          });

          test(
              'prints error message and throws ShorebirdNotInitializedException',
              () async {
            await expectLater(
              runWithOverrides(
                () => shorebirdValidator.validatePreconditions(
                  checkShorebirdInitialized: true,
                ),
              ),
              throwsA(isA<ShorebirdNotInitializedException>()),
            );
            verifyInOrder([
              () => logger.err(
                    '''Unable to find shorebird.yaml. Are you in a shorebird app directory?''',
                  ),
              () => logger.info(
                    '''If you have not yet initialized your app, run ${lightCyan.wrap('shorebird init')} to get started.''',
                  ),
            ]);
          });
        });

        group("when pubspec.yaml doesn't contain shorebird.yaml as an asset",
            () {
          setUp(() {
            when(() => shorebirdEnv.hasShorebirdYaml).thenReturn(true);
            when(() => shorebirdEnv.pubspecContainsShorebirdYaml).thenReturn(
              false,
            );
          });

          test(
              'prints error message and throws ShorebirdNotInitializedException',
              () async {
            await expectLater(
              runWithOverrides(
                () => shorebirdValidator.validatePreconditions(
                  checkShorebirdInitialized: true,
                ),
              ),
              throwsA(isA<ShorebirdNotInitializedException>()),
            );
            verifyInOrder([
              () => logger.err(
                    '''Your pubspec.yaml does not have shorebird.yaml as a flutter asset.''',
                  ),
              () => logger.info('''
To fix, update your pubspec.yaml to include the following:

  flutter:
    assets:
      - shorebird.yaml # Add this line
'''),
            ]);
          });
        });
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

      test(
          '''throws UnsupportedContextException if validator cannot be run in current context''',
          () async {
        const errorMessage = 'Cannot run in this context';
        when(() => validator.canRunInCurrentContext()).thenReturn(false);
        when(() => validator.incorrectContextMessage).thenReturn(errorMessage);
        await expectLater(
          runWithOverrides(
            () => shorebirdValidator.validatePreconditions(
              validators: [validator],
            ),
          ),
          throwsA(isA<UnsupportedContextException>()),
        );
        verify(() => logger.err(errorMessage)).called(1);
      });
    });
  });
}

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/credential_source.dart';
import 'package:shorebird_cli/src/auth/github_actions_oidc.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/apple/apple.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(ShorebirdValidator, () {
    late Apple apple;
    late Auth auth;
    late ShorebirdLogger logger;
    late TestNativePlatform platform;
    late Validator validator;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          appleRef.overrideWith(() => apple),
          authRef.overrideWith(() => auth),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      apple = MockApple();
      auth = MockAuth();
      logger = MockShorebirdLogger();
      platform = TestNativePlatform(
        operatingSystem: NativePlatform.macOS,
        environment: {},
      );
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
      test('throws UnsupportedOperatingSystemException '
          'when the operating system is not supported', () async {
        platform = platform.copyWith(operatingSystem: NativePlatform.linux);
        const supportedOperatingSystems = {
          NativePlatform.macOS,
          NativePlatform.windows,
        };
        await expectLater(
          runWithOverrides(
            () => shorebirdValidator.validatePreconditions(
              supportedOperatingSystems: supportedOperatingSystems,
            ),
          ),
          throwsA(
            isA<UnsupportedOperatingSystemException>()
                .having(
                  (e) => e.message,
                  'message',
                  'This command is only supported on macos, windows '
                      '(this machine is running linux).',
                )
                .having((e) => e.hint, 'hint', isNull),
          ),
        );
        verify(
          () => logger.err(
            '''This command is only supported on macos, windows (this machine is running linux).''',
          ),
        ).called(1);
      });

      test('throws UserNotAuthorizedException '
          'when user is not authenticated', () async {
        when(() => auth.isAuthenticated).thenReturn(false);
        await expectLater(
          runWithOverrides(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: true,
            ),
          ),
          throwsA(
            isA<UserNotAuthorizedException>()
                .having(
                  (e) => e.message,
                  'message',
                  'You must be logged in to run this command.',
                )
                .having(
                  (e) => e.hint,
                  'hint',
                  'If you already have an account, run `shorebird login` to '
                      "sign in. If you don't have a Shorebird account, go to "
                      'https://console.shorebird.dev to create one.',
                ),
          ),
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

      test('reports why a way of authenticating this environment was meant '
          'to use cannot be used', () async {
        when(() => auth.isAuthenticated).thenReturn(false);
        when(() => auth.unavailableCredentialsReason).thenReturn(
          const CredentialSourceException(
            'Signing in with GitHub Actions OIDC requires '
            'SHOREBIRD_PROJECT_ID.',
            hint: 'Set SHOREBIRD_PROJECT_ID.',
          ),
        );
        platform = platform.copyWith(
          environment: {githubActionsEnvVar: 'true'},
        );
        await expectLater(
          runWithOverrides(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: true,
            ),
          ),
          throwsA(
            isA<UserNotAuthorizedException>()
                .having(
                  (e) => e.message,
                  'message',
                  'Signing in with GitHub Actions OIDC requires '
                      'SHOREBIRD_PROJECT_ID.',
                )
                .having((e) => e.hint, 'hint', 'Set SHOREBIRD_PROJECT_ID.'),
          ),
        );
        verifyInOrder([
          () => logger.err(
            'Signing in with GitHub Actions OIDC requires '
            'SHOREBIRD_PROJECT_ID.',
          ),
          () => logger.info('Set SHOREBIRD_PROJECT_ID.'),
        ]);
        verifyNever(
          () => logger.err('You must be logged in to run this command.'),
        );
      });

      test('reports an unavailable reason without a hint', () async {
        when(() => auth.isAuthenticated).thenReturn(false);
        when(() => auth.unavailableCredentialsReason).thenReturn(
          const CredentialSourceException('Cannot sign in.'),
        );
        await expectLater(
          runWithOverrides(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: true,
            ),
          ),
          throwsA(
            isA<UserNotAuthorizedException>().having(
              (e) => e.hint,
              'hint',
              isNull,
            ),
          ),
        );
        verify(() => logger.err('Cannot sign in.')).called(1);
        verifyNever(() => logger.info(any()));
      });

      test('points at GitHub Actions OIDC when running in GitHub Actions '
          'and the user is not authenticated', () async {
        when(() => auth.isAuthenticated).thenReturn(false);
        platform = platform.copyWith(
          environment: {githubActionsEnvVar: 'true'},
        );
        const oidcHint =
            'To sign in from GitHub Actions without a stored secret, grant '
            'the job `permissions: id-token: write`, set SHOREBIRD_PROJECT_ID '
            'to the id of your project, and add a GitHub Actions trust rule '
            'for this workflow at https://console.shorebird.dev.';
        const apiKeyHint =
            'Or set SHOREBIRD_TOKEN to a Shorebird API key from '
            'https://console.shorebird.dev.';
        await expectLater(
          runWithOverrides(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: true,
            ),
          ),
          throwsA(
            isA<UserNotAuthorizedException>().having(
              (e) => e.hint,
              'hint',
              '$oidcHint $apiKeyHint',
            ),
          ),
        );
        verifyInOrder([
          () => logger.err('You must be logged in to run this command.'),
          () => logger.info(oidcHint),
          () => logger.info(apiKeyHint),
        ]);
      });

      group(
        '''when shorebird has not been properly initialized for the current app''',
        () {
          group("when shorebird.yaml doesn't exist", () {
            setUp(() {
              when(() => shorebirdEnv.hasShorebirdYaml).thenReturn(false);
            });

            test(
              '''prints error message and throws ShorebirdNotInitializedException''',
              () async {
                await expectLater(
                  runWithOverrides(
                    () => shorebirdValidator.validatePreconditions(
                      checkShorebirdInitialized: true,
                    ),
                  ),
                  throwsA(
                    isA<ShorebirdNotInitializedException>()
                        .having(
                          (e) => e.message,
                          'message',
                          'Unable to find shorebird.yaml. Are you in a '
                              'shorebird app directory?',
                        )
                        .having(
                          (e) => e.hint,
                          'hint',
                          'If you have not yet initialized your app, run '
                              '`shorebird init` to get started.',
                        ),
                  ),
                );
                verifyInOrder([
                  () => logger.err(
                    '''Unable to find shorebird.yaml. Are you in a shorebird app directory?''',
                  ),
                  () => logger.info(
                    '''If you have not yet initialized your app, run ${lightCyan.wrap('shorebird init')} to get started.''',
                  ),
                ]);
              },
            );
          });

          group("when pubspec.yaml doesn't contain "
              'shorebird.yaml as an asset', () {
            setUp(() {
              when(() => shorebirdEnv.hasShorebirdYaml).thenReturn(true);
              when(
                () => shorebirdEnv.pubspecContainsShorebirdYaml,
              ).thenReturn(false);
            });

            test(
              '''prints error message and throws ShorebirdNotInitializedException''',
              () async {
                await expectLater(
                  runWithOverrides(
                    () => shorebirdValidator.validatePreconditions(
                      checkShorebirdInitialized: true,
                    ),
                  ),
                  throwsA(
                    isA<ShorebirdNotInitializedException>()
                        .having(
                          (e) => e.message,
                          'message',
                          'Your pubspec.yaml does not have shorebird.yaml as '
                              'a flutter asset.',
                        )
                        .having(
                          (e) => e.hint,
                          'hint',
                          'Add shorebird.yaml to the flutter assets in your '
                              'pubspec.yaml.',
                        ),
                  ),
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
              },
            );
          });
        },
      );

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
          throwsA(
            isA<ValidationFailedException>()
                .having(
                  (e) => e.message,
                  'message',
                  'Aborting due to validation errors. test issue',
                )
                .having(
                  (e) => e.hint,
                  'hint',
                  '1 issue can be fixed automatically with '
                      '`shorebird doctor --fix`.',
                ),
          ),
        );
        verify(() => validator.validate()).called(1);
        verify(
          () => logger.err('Aborting due to validation errors.'),
        ).called(1);
        verify(
          () => logger.info('${red.wrap('[✗]')} ${issue.message}'),
        ).called(1);
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
          when(
            () => validator.incorrectContextMessage,
          ).thenReturn(errorMessage);
          await expectLater(
            runWithOverrides(
              () => shorebirdValidator.validatePreconditions(
                validators: [validator],
              ),
            ),
            throwsA(
              isA<UnsupportedContextException>().having(
                (e) => e.message,
                'message',
                errorMessage,
              ),
            ),
          );
          verify(() => logger.err(errorMessage)).called(1);
        },
      );

      test('reports only the error issues, and no hint when none is '
          'fixable', () async {
        const issues = [
          ValidationIssue(
            message: 'a warning',
            severity: ValidationIssueSeverity.warning,
          ),
          ValidationIssue(
            message: 'first error.',
            severity: ValidationIssueSeverity.error,
          ),
          ValidationIssue(
            message: 'second error.',
            severity: ValidationIssueSeverity.error,
          ),
        ];
        when(() => validator.canRunInCurrentContext()).thenReturn(true);
        when(() => validator.validate()).thenAnswer((_) async => issues);
        await expectLater(
          runWithOverrides(
            () => shorebirdValidator.validatePreconditions(
              validators: [validator],
            ),
          ),
          throwsA(
            isA<ValidationFailedException>()
                .having(
                  (e) => e.message,
                  'message',
                  'Aborting due to validation errors. first error. '
                      'second error.',
                )
                .having((e) => e.hint, 'hint', isNull),
          ),
        );
      });

      test('uses a generic message when the validator gives no context '
          'message', () async {
        when(() => validator.canRunInCurrentContext()).thenReturn(false);
        when(() => validator.incorrectContextMessage).thenReturn(null);
        await expectLater(
          runWithOverrides(
            () => shorebirdValidator.validatePreconditions(
              validators: [validator],
            ),
          ),
          throwsA(
            isA<UnsupportedContextException>().having(
              (e) => e.message,
              'message',
              'This command cannot run in the current context.',
            ),
          ),
        );
      });
    });

    group('validateFlavors', () {
      late ShorebirdYaml shorebirdYaml;

      setUp(() {
        when(
          () => shorebirdEnv.getShorebirdYaml(),
        ).thenAnswer((_) => shorebirdYaml);
      });

      group('when shorebird.yaml has flavors', () {
        setUp(() {
          shorebirdYaml = const ShorebirdYaml(
            appId: 'test',
            flavors: {'flavorA': 'flavorA'},
          );
        });

        setUp(() {
          when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
        });

        group('when platform does not support flavors', () {
          group('when a flavor arg is provided', () {
            test('validation fails', () async {
              await expectLater(
                runWithOverrides(
                  () => shorebirdValidator.validateFlavors(
                    flavorArg: 'flavorA',
                    releasePlatform: ReleasePlatform.windows,
                  ),
                ),
                throwsA(
                  isA<ValidationFailedException>()
                      .having(
                        (e) => e.message,
                        'message',
                        'Flavors are not supported on this platform.',
                      )
                      .having(
                        (e) => e.hint,
                        'hint',
                        'Re-run this command without the --flavor argument. '
                            'The app id test will be used.',
                      ),
                ),
              );

              verify(
                () => logger.err('Flavors are not supported on this platform.'),
              ).called(1);
              verify(
                () => logger.info(
                  '''Please re-run this command without the --flavor argument. The app id ${lightCyan.wrap('test')} will be used.''',
                ),
              ).called(1);
            });
          });

          group('when no flavor arg is provided', () {
            test('passes validation', () async {
              await expectLater(
                runWithOverrides(
                  () => shorebirdValidator.validateFlavors(
                    flavorArg: null,
                    releasePlatform: ReleasePlatform.windows,
                  ),
                ),
                completes,
              );
            });
          });
        });

        group('when platform supports flavors', () {
          group('when no flavor is specified', () {
            test('logs warning and fails validation', () async {
              await expectLater(
                runWithOverrides(
                  () => shorebirdValidator.validateFlavors(
                    flavorArg: null,
                    releasePlatform: ReleasePlatform.android,
                  ),
                ),
                completes,
              );
              verify(
                () => logger.warn(
                  '''
The project has flavors flavorA, but no --flavor argument was provided.
The default app id test will be used. Pass --flavor=<name> to target a flavor.''',
                ),
              ).called(1);
            });
          });

          group('when the Xcode project has no scheme for the flavor', () {
            setUp(() {
              when(
                () => apple.flavors(
                  platform: ApplePlatform.ios,
                  includeUserSchemes: true,
                ),
              ).thenReturn({});
            });

            test('fails validation before building', () async {
              await expectLater(
                runWithOverrides(
                  () => shorebirdValidator.validateFlavors(
                    flavorArg: 'flavorA',
                    releasePlatform: ReleasePlatform.ios,
                  ),
                ),
                throwsA(
                  isA<ValidationFailedException>().having(
                    (e) => e.message,
                    'message',
                    contains('The iOS project has no Xcode scheme'),
                  ),
                ),
              );
            });

            test('does not warn when no flavor is given', () async {
              await expectLater(
                runWithOverrides(
                  () => shorebirdValidator.validateFlavors(
                    flavorArg: null,
                    releasePlatform: ReleasePlatform.ios,
                  ),
                ),
                completes,
              );
              verifyNever(() => logger.warn(any()));
            });
          });

          group('when the Xcode schemes cannot be read', () {
            setUp(() {
              when(
                () => apple.flavors(
                  platform: ApplePlatform.ios,
                  includeUserSchemes: true,
                ),
              ).thenThrow(Exception('no schemes'));
            });

            test('passes validation', () async {
              await expectLater(
                runWithOverrides(
                  () => shorebirdValidator.validateFlavors(
                    flavorArg: 'flavorA',
                    releasePlatform: ReleasePlatform.ios,
                  ),
                ),
                completes,
              );
            });
          });

          group('when a flavor arg is provided that exists in the project', () {
            test('passes validation', () async {
              await expectLater(
                runWithOverrides(
                  () => shorebirdValidator.validateFlavors(
                    flavorArg: 'flavorA',
                    releasePlatform: ReleasePlatform.android,
                  ),
                ),
                completes,
              );
              verifyZeroInteractions(apple);
            });
          });
        });
      });

      group('when shorebird.yaml does not have flavors', () {
        setUp(() {
          shorebirdYaml = const ShorebirdYaml(appId: 'test');
        });

        group('when no flavor arg is provided', () {
          test('passes validation', () async {
            await expectLater(
              runWithOverrides(
                () => shorebirdValidator.validateFlavors(
                  flavorArg: null,
                  releasePlatform: ReleasePlatform.android,
                ),
              ),
              completes,
            );
          });

          group('when a flavor arg is provided', () {
            test('fails validation', () async {
              await expectLater(
                runWithOverrides(
                  () => shorebirdValidator.validateFlavors(
                    flavorArg: 'flavorA',
                    releasePlatform: ReleasePlatform.android,
                  ),
                ),
                throwsA(
                  isA<ValidationFailedException>().having(
                    (e) => e.message,
                    'message',
                    isNotEmpty,
                  ),
                ),
              );
            });
          });
        });
      });
    });
  });
}

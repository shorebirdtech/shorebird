import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(FlavorValidator, () {
    const appId = 'app-id';
    const flavors = {'flavorA': 'flavorA', 'flavorB': 'flavorB'};
    const shorebirdYamlWithoutFlavors = ShorebirdYaml(appId: appId);
    const shorebirdYamlWithFlavors = ShorebirdYaml(
      appId: appId,
      flavors: flavors,
    );
    late ShorebirdEnv shorebirdEnv;

    late FlavorValidator validator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {shorebirdEnvRef.overrideWith(() => shorebirdEnv)},
      );
    }

    setUp(() {
      shorebirdEnv = MockShorebirdEnv();
      validator = FlavorValidator(flavorArg: 'flavor');
    });

    group('description', () {
      test('is not empty', () {
        expect(validator.description, isNotEmpty);
      });
    });

    group('validate', () {
      group('when project does not have flavors', () {
        setUp(() {
          when(
            () => shorebirdEnv.getShorebirdYaml(),
          ).thenReturn(shorebirdYamlWithoutFlavors);
        });

        group('when flavor arg is provided', () {
          setUp(() {
            validator = FlavorValidator(flavorArg: 'flavor');
          });

          test('returns no validation issues', () async {
            final issues = await runWithOverrides(validator.validate);
            expect(issues, isNot(isEmpty));
            expect(
              issues.first.message,
              equals(
                '''The project does not have any flavors defined (no "flavors" in shorebird.yaml), but --flavor was provided. Re-run without --flavor, or run "shorebird init" to detect flavors.''',
              ),
            );
          });
        });

        group('when no flavor arg is provided', () {
          setUp(() {
            validator = FlavorValidator(flavorArg: null);
          });

          test('returns no validation issues', () async {
            final issues = await runWithOverrides(validator.validate);
            expect(issues, isEmpty);
          });
        });
      });

      group('when project has flavors', () {
        setUp(() {
          when(
            () => shorebirdEnv.getShorebirdYaml(),
          ).thenReturn(shorebirdYamlWithFlavors);
        });

        group('when flavor arg is provided', () {
          group('when flavor exists in project', () {
            setUp(() {
              validator = FlavorValidator(flavorArg: 'flavorA');
            });

            test('returns no issues', () async {
              final issues = await runWithOverrides(validator.validate);
              expect(issues, isEmpty);
            });
          });

          group('when flavor does not exist in project', () {
            setUp(() {
              validator = FlavorValidator(flavorArg: 'flavorC');
            });

            test('returns validation error', () async {
              final issues = await runWithOverrides(validator.validate);
              expect(
                issues,
                equals([
                  ValidationIssue.error(
                    message:
                        '''This project does not have a flavor named "flavorC". Pass one of: flavorA, flavorB (from "flavors" in shorebird.yaml).''',
                  ),
                ]),
              );
            });
          });
        });

        group('when the platform project has no matching flavor', () {
          test('returns an error naming the default app id', () async {
            validator = FlavorValidator(
              flavorArg: 'flavorA',
              platform: ReleasePlatform.ios,
              platformFlavors: {},
            );
            final issues = await runWithOverrides(validator.validate);
            expect(
              issues,
              equals([
                ValidationIssue.error(
                  message:
                      '''The iOS project has no Xcode scheme for flavor "flavorA", so it cannot be built with --flavor=flavorA. Add a scheme named "flavorA" (see https://docs.shorebird.dev/code-push/guides/flavors/ios/), or re-run without --flavor to use the default app id $appId.''',
                ),
              ]),
            );
          });

          test(
            'suggests the shorebird.yaml flavors that have a scheme',
            () async {
              when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(
                const ShorebirdYaml(
                  appId: appId,
                  flavors: {'Prod': 'prod-id', 'Dev': 'dev-id'},
                ),
              );
              validator = FlavorValidator(
                flavorArg: 'Prod',
                platform: ReleasePlatform.ios,
                platformFlavors: {'dev', 'staging'},
              );
              final issues = await runWithOverrides(validator.validate);
              expect(
                issues,
                equals([
                  ValidationIssue.error(
                    message:
                        '''The iOS project has no Xcode scheme for flavor "Prod", so it cannot be built with --flavor=Prod. Add a scheme named "Prod" (see https://docs.shorebird.dev/code-push/guides/flavors/ios/), or pass one of: Dev.''',
                  ),
                ]),
              );
            },
          );

          test('links no guide for macOS', () async {
            validator = FlavorValidator(
              flavorArg: 'flavorA',
              platform: ReleasePlatform.macos,
              platformFlavors: {},
            );
            final issues = await runWithOverrides(validator.validate);
            expect(
              issues,
              equals([
                ValidationIssue.error(
                  message:
                      '''The macOS project has no Xcode scheme for flavor "flavorA", so it cannot be built with --flavor=flavorA. Add a scheme named "flavorA", or re-run without --flavor to use the default app id $appId.''',
                ),
              ]),
            );
          });

          test('matches scheme names case-insensitively', () async {
            when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(
              const ShorebirdYaml(appId: appId, flavors: {'Staging': 'id'}),
            );
            validator = FlavorValidator(
              flavorArg: 'Staging',
              platform: ReleasePlatform.ios,
              platformFlavors: {'staging'},
            );
            final issues = await runWithOverrides(validator.validate);
            expect(issues, isEmpty);
          });

          test('does not warn about a missing --flavor', () async {
            validator = FlavorValidator(
              flavorArg: null,
              platform: ReleasePlatform.ios,
              platformFlavors: {},
            );
            final issues = await runWithOverrides(validator.validate);
            expect(issues, isEmpty);
          });
        });

        group('when no flavor arg is provided', () {
          setUp(() {
            validator = FlavorValidator(flavorArg: null);
          });

          test('returns validation warning', () async {
            final issues = await runWithOverrides(validator.validate);
            expect(
              issues,
              equals([
                ValidationIssue.warning(
                  message: '''
The project has flavors flavorA, flavorB, but no --flavor argument was provided.
The default app id $appId will be used. Pass --flavor=<name> to target a flavor.''',
                ),
              ]),
            );
          });
        });
      });
    });
  });
}

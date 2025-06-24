import 'dart:io' hide Platform;

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/init_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/apple.dart';
import 'package:shorebird_cli/src/pubspec_editor.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(InitCommand, () {
    const version = '1.2.3';
    const appId = 'test_app_id';
    const appName = 'test_app_name';
    const app = App(id: appId, displayName: appName);
    const pubspecYamlContent =
        '''
name: $appName
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"''';
    const organizationId = 123;

    late ArgResults argResults;
    late Doctor doctor;
    late Gradlew gradlew;
    late CodePushClientWrapper codePushClientWrapper;
    late File shorebirdYamlFile;
    late ShorebirdYaml shorebirdYaml;
    late Directory projectRoot;
    late File pubspecYamlFile;
    late ShorebirdLogger logger;
    late Platform platform;
    late Progress progress;
    late PubspecEditor pubspecEditor;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late Apple apple;
    late InitCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          gradlewRef.overrideWith(() => gradlew),
          appleRef.overrideWith(() => apple),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          shorebirdProcessRef.overrideWith(() => shorebirdProcess),
          pubspecEditorRef.overrideWith(() => pubspecEditor),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(ApplePlatform.ios);
      registerFallbackValue(MockDirectory());
    });

    setUp(() {
      argResults = MockArgResults();
      doctor = MockDoctor();
      gradlew = MockGradlew();
      codePushClientWrapper = MockCodePushClientWrapper();
      apple = MockApple();
      shorebirdYaml = MockShorebirdYaml();
      shorebirdYamlFile = MockFile();
      pubspecYamlFile = MockFile();
      projectRoot = Directory.systemTemp.createTempSync();
      pubspecEditor = MockPubspecEditor();
      logger = MockShorebirdLogger();
      platform = MockPlatform();
      progress = MockProgress();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();

      when(() => codePushClientWrapper.getOrganizationMemberships()).thenAnswer(
        (_) async => [
          OrganizationMembership(
            role: OrganizationRole.owner,
            organization: Organization.forTest(id: organizationId),
          ),
        ],
      );
      when(
        () => codePushClientWrapper.createApp(
          appName: any(named: 'appName'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => app);
      when(
        () => doctor.runValidators(any(), applyFixes: any(named: 'applyFixes')),
      ).thenAnswer((_) async => {});
      when(() => doctor.generalValidators).thenReturn([]);
      when(
        () => gradlew.isDaemonAvailable(any()),
      ).thenAnswer((_) async => true);
      when(
        () => shorebirdEnv.getShorebirdYamlFile(cwd: any(named: 'cwd')),
      ).thenReturn(shorebirdYamlFile);
      when(
        () => shorebirdEnv.getPubspecYamlFile(cwd: any(named: 'cwd')),
      ).thenReturn(pubspecYamlFile);
      when(() => shorebirdEnv.getFlutterProjectRoot()).thenReturn(projectRoot);
      when(
        () => pubspecYamlFile.readAsStringSync(),
      ).thenReturn(pubspecYamlContent);
      when(
        () => pubspecYamlFile.uri,
      ).thenReturn(File(p.join('pubspec.yaml')).uri);
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(appName);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => gradlew.productFlavors(any())).thenAnswer((_) async => {});
      when(() => platform.isMacOS).thenReturn(true);
      when(() => shorebirdEnv.hasPubspecYaml).thenReturn(true);
      when(
        () => shorebirdEnv.getPubspecYaml(),
      ).thenReturn(Pubspec.parse(pubspecYamlContent));
      when(() => shorebirdEnv.hasShorebirdYaml).thenReturn(false);
      when(() => shorebirdEnv.pubspecContainsShorebirdYaml).thenReturn(false);
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => apple.flavors(platform: any(named: 'platform')),
      ).thenReturn(null);

      command = runWithOverrides(InitCommand.new)..testArgResults = argResults;
    });

    test('exits when validation fails', () async {
      final exception = ValidationFailedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenThrow(exception);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(exception.exitCode.code)),
      );
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
        ),
      ).called(1);
    });

    test('throws no input error when pubspec.yaml is not found.', () async {
      when(() => shorebirdEnv.hasPubspecYaml).thenReturn(false);
      final exitCode = await runWithOverrides(command.run);
      verify(
        () => logger.err('''
Could not find a "pubspec.yaml".
Please make sure you are running "shorebird init" from within your Flutter project.
'''),
      ).called(1);
      expect(exitCode, ExitCode.noInput.code);
    });

    test('throws software error when pubspec.yaml is malformed.', () async {
      final exception = Exception('oops');
      when(() => shorebirdEnv.hasPubspecYaml).thenThrow(exception);
      final exitCode = await runWithOverrides(command.run);
      verify(
        () => logger.err('Error parsing "pubspec.yaml": $exception'),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws software error when shorebird.yaml already exists', () async {
      when(() => shorebirdEnv.hasShorebirdYaml).thenReturn(true);
      final exitCode = await runWithOverrides(command.run);
      verify(
        () => logger.err(
          'A "shorebird.yaml" file already exists and seems up-to-date.',
        ),
      ).called(1);
      verify(
        () => logger.info(
          '''If you want to reinitialize Shorebird, please run ${lightCyan.wrap('shorebird init --force')}.''',
        ),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('does not prompt for name when unable to accept user input', () async {
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);
      await runWithOverrides(command.run);
      verifyNever(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      );
      verify(
        () => codePushClientWrapper.createApp(
          appName: appName,
          organizationId: organizationId,
        ),
      ).called(1);
    });

    test('does not prompt for name when --force', () async {
      when(() => argResults['force']).thenReturn(true);
      await runWithOverrides(command.run);
      verifyNever(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      );
      verify(
        () => codePushClientWrapper.createApp(
          appName: appName,
          organizationId: organizationId,
        ),
      ).called(1);
    });

    test('--force overwrites existing shorebird.yaml', () async {
      when(() => shorebirdEnv.hasShorebirdYaml).thenReturn(true);
      when(() => argResults['force']).thenReturn(true);
      final exitCode = await runWithOverrides(command.run);
      verifyNever(
        () => logger.err(
          'A "shorebird.yaml" file already exists and seems up-to-date.',
        ),
      );
      expect(exitCode, ExitCode.success.code);
      verify(
        () => shorebirdYamlFile.writeAsStringSync(
          any(that: contains('app_id: $appId')),
        ),
      ).called(1);
    });

    test('gracefully handles missing android project exceptions', () async {
      when(
        () => gradlew.isDaemonAvailable(any()),
      ).thenThrow(const MissingAndroidProjectException(''));
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
      verifyNever(() => gradlew.startDaemon(any()));
    });

    test('throws when unable to initialize gradle wrapper', () async {
      when(() => gradlew.isDaemonAvailable(any())).thenThrow(Exception('oops'));
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.software.code);
      verifyNever(() => gradlew.startDaemon(any()));
      verify(() => logger.err('Unable to initialize gradlew.')).called(1);
    });

    test('starts gradle daemon if needed and throws on error', () async {
      when(
        () => gradlew.isDaemonAvailable(any()),
      ).thenAnswer((_) async => false);
      when(() => gradlew.startDaemon(any())).thenThrow(Exception('oops'));
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.software.code);
      verify(() => gradlew.startDaemon(projectRoot.path)).called(1);
      verify(() => logger.err('Unable to start gradle daemon.')).called(1);
    });

    test('starts gradle daemon if needed and streams logs', () async {
      when(
        () => gradlew.isDaemonAvailable(any()),
      ).thenAnswer((_) async => false);
      when(() => gradlew.startDaemon(any())).thenAnswer((_) async {});
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
      verify(() => gradlew.startDaemon(projectRoot.path)).called(1);
      verify(() => gradlew.isDaemonAvailable(projectRoot.path)).called(1);
    });

    test('fails when an error occurs while extracting flavors', () async {
      final exception = Exception('oops');
      when(() => gradlew.productFlavors(any())).thenThrow(exception);
      final exitCode = await runWithOverrides(command.run);
      verify(() => logger.progress('Detecting product flavors')).called(1);
      verify(
        () => logger.err(
          any(that: contains('Unable to extract product flavors.')),
        ),
      ).called(1);
      verify(() => progress.fail()).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws software error when error occurs creating app.', () async {
      final error = Exception('oops');
      when(
        () => codePushClientWrapper.createApp(
          appName: any(named: 'appName'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenThrow(error);
      final exitCode = await runWithOverrides(command.run);
      verify(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).called(1);
      verify(() => logger.err('$error')).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    group('when user has no organizations', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getOrganizationMemberships(),
        ).thenAnswer((_) async => []);
      });

      test('exits with software error code', () async {
        final exitCode = await runWithOverrides(command.run);
        expect(exitCode, equals(ExitCode.software.code));
        verify(
          () => logger.err(
            '''You do not have any organizations. This should never happen. Please contact us on Discord or send us an email at contact@shorebird.dev.''',
          ),
        ).called(1);
      });
    });

    group('when organization id argument is provided', () {
      group('when arg is not a parseable int', () {
        setUp(() {
          when(() => argResults['organization-id']).thenReturn('not-an-int');
        });

        test('exits with usage error code', () async {
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.usage.code));
          verify(
            () => logger.err('Invalid organization ID: "not-an-int"'),
          ).called(1);
        });

        group('when no organization with matching id exists', () {
          setUp(() {
            when(() => argResults['organization-id']).thenReturn('999999');
          });

          test('exits with usage error code', () async {
            final exitCode = await runWithOverrides(command.run);
            expect(exitCode, equals(ExitCode.usage.code));
            verify(
              () => logger.err('Organization with ID "999999" not found.'),
            ).called(1);
          });
        });

        group('when organization with matching id exists', () {
          setUp(() {
            when(
              () => argResults['organization-id'],
            ).thenReturn('$organizationId');
          });

          test('creates app with provided organization id', () async {
            final exitCode = await runWithOverrides(command.run);
            expect(exitCode, equals(ExitCode.success.code));
            verify(
              () => codePushClientWrapper.createApp(
                appName: appName,
                organizationId: organizationId,
              ),
            ).called(1);
          });
        });
      });
    });

    group('when user has only one organization', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getOrganizationMemberships(),
        ).thenAnswer(
          (_) async => [
            OrganizationMembership(
              role: OrganizationRole.owner,
              organization: Organization.forTest(id: organizationId),
            ),
          ],
        );
      });

      test(
        'does not prompt for organization, uses that org id to create app',
        () async {
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.success.code));
          verifyNever(
            () => logger.chooseOne(
              'Which organization should this app belong to?',
              choices: any(named: 'choices'),
            ),
          );
          verify(
            () => codePushClientWrapper.createApp(
              appName: appName,
              organizationId: organizationId,
            ),
          ).called(1);
        },
      );
    });

    group('when user has multiple organizations', () {
      final org1 = Organization.forTest(name: 'org1', id: 1);
      final org2 = Organization.forTest(
        name: 'org2',
        id: 2,
        organizationType: OrganizationType.team,
      );

      setUp(() {
        when(
          () => codePushClientWrapper.getOrganizationMemberships(),
        ).thenAnswer(
          (_) async => [
            OrganizationMembership(
              role: OrganizationRole.owner,
              organization: org1,
            ),
            OrganizationMembership(
              role: OrganizationRole.owner,
              organization: org2,
            ),
          ],
        );
        when(
          () => logger.chooseOne<Organization>(
            'Which organization should this app belong to?',
            choices: any(named: 'choices'),
            display: any(named: 'display'),
          ),
        ).thenReturn(org2);
      });

      test(
        'prompts for organization and uses that org id to create app',
        () async {
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.success.code));
          final capturedDisplay =
              verify(
                    () => logger.chooseOne<Organization>(
                      'Which organization should this app belong to?',
                      choices: [org1, org2],
                      display: captureAny(named: 'display'),
                    ),
                  ).captured.single
                  as String Function(Organization);
          expect(capturedDisplay(org1), equals(org1.name));
          expect(capturedDisplay(org2), equals(org2.name));
          verify(
            () => codePushClientWrapper.createApp(
              appName: appName,
              organizationId: org2.id,
            ),
          ).called(1);
        },
      );
    });

    group('on non MacOS', () {
      setUp(() {
        when(() => platform.isMacOS).thenReturn(false);
      });

      group('when ios directory is empty', () {
        setUp(() {
          when(
            () => apple.flavors(platform: any(named: 'platform')),
          ).thenThrow(MissingXcodeProjectException(projectRoot.path));
        });

        test('exits with software error code', () async {
          Directory(
            p.join(projectRoot.path, 'ios', 'Runner.xcodeproj'),
          ).createSync(recursive: true);
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.software.code));
          verify(
            () => logger.err(
              any(that: contains('Could not find an Xcode project in')),
            ),
          ).called(1);
        });
      });

      test('creates shorebird for an android-only app', () async {
        final exitCode = await runWithOverrides(command.run);
        expect(exitCode, equals(ExitCode.success.code));
        verify(
          () => shorebirdYamlFile.writeAsStringSync(
            any(that: contains('app_id: $appId')),
          ),
        ).called(1);
      });

      group('when --display-name is provided', () {
        const displayName = 'custom-display-name';

        setUp(() {
          when(() => argResults['display-name']).thenReturn(displayName);
        });

        test(
          'does not prompt for display name and uses correct display name',
          () async {
            final exitCode = await runWithOverrides(command.run);
            expect(exitCode, equals(ExitCode.success.code));
            verify(
              () => shorebirdYamlFile.writeAsStringSync(
                any(that: contains('app_id: $appId')),
              ),
            ).called(1);
            verifyNever(() => logger.prompt(any()));
            verify(
              () => codePushClientWrapper.createApp(
                appName: displayName,
                organizationId: organizationId,
              ),
            ).called(1);
          },
        );
      });

      test('creates shorebird for an app without flavors', () async {
        when(
          () => gradlew.productFlavors(any()),
        ).thenThrow(MissingAndroidProjectException(projectRoot.path));
        File(
          p.join(
            projectRoot.path,
            'ios',
            'Runner.xcodeproj',
            'xcshareddata',
            'xcschemes',
            'Runner.xcscheme',
          ),
        ).createSync(recursive: true);
        final exitCode = await runWithOverrides(command.run);
        expect(exitCode, equals(ExitCode.success.code));
        verify(
          () => shorebirdYamlFile.writeAsStringSync(
            any(that: contains('app_id: $appId')),
          ),
        ).called(1);
        verify(
          () => progress.complete('No product flavors detected.'),
        ).called(1);
      });

      test('creates shorebird for an app with flavors', () async {
        const appIds = ['test-appId-1', 'test-appId-2'];
        var index = 0;
        when(
          () => codePushClientWrapper.createApp(
            appName: any(named: 'appName'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((invocation) async {
          final appName = invocation.namedArguments[#appName] as String?;
          return App(id: appIds[index++], displayName: appName ?? '-');
        });
        when(
          () => gradlew.productFlavors(any()),
        ).thenThrow(MissingAndroidProjectException(projectRoot.path));
        when(
          () => apple.flavors(platform: any(named: 'platform')),
        ).thenReturn({'internal', 'stable'});
        final exitCode = await runWithOverrides(command.run);
        expect(exitCode, equals(ExitCode.success.code));
        verify(
          () => progress.complete('2 product flavors detected:'),
        ).called(1);
        verify(() => logger.info('  - internal')).called(1);
        verify(() => logger.info('  - stable')).called(1);
        verify(
          () => shorebirdYamlFile.writeAsStringSync(
            any(
              that: contains('''
app_id: ${appIds[0]}
flavors:
  internal: ${appIds[0]}
  stable: ${appIds[1]}'''),
            ),
          ),
        ).called(1);
        verifyInOrder([
          () => codePushClientWrapper.createApp(
            appName: '$appName (internal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (stable)',
            organizationId: organizationId,
          ),
        ]);
      });
    });

    test('creates shorebird.yaml for an app without flavors', () async {
      await runWithOverrides(command.run);
      verify(
        () => shorebirdYamlFile.writeAsStringSync(
          any(that: contains('app_id: $appId')),
        ),
      );
    });

    group('creates shorebird.yaml for an app with flavors', () {
      test('android only', () async {
        final appIds = [
          'test-appId-1',
          'test-appId-2',
          'test-appId-3',
          'test-appId-4',
          'test-appId-5',
          'test-appId-6',
        ];
        var index = 0;
        when(() => gradlew.productFlavors(any())).thenAnswer(
          (_) async => {
            'development',
            'developmentInternal',
            'production',
            'productionInternal',
            'staging',
            'stagingInternal',
          },
        );
        when(
          () => codePushClientWrapper.createApp(
            appName: any(named: 'appName'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((invocation) async {
          final appName = invocation.namedArguments[#appName] as String?;
          return App(id: appIds[index++], displayName: appName ?? '--');
        });
        await runWithOverrides(command.run);
        verify(
          () => shorebirdYamlFile.writeAsStringSync(
            any(
              that: contains('''
app_id: ${appIds[0]}
flavors:
  development: ${appIds[0]}
  developmentInternal: ${appIds[1]}
  production: ${appIds[2]}
  productionInternal: ${appIds[3]}
  staging: ${appIds[4]}
  stagingInternal: ${appIds[5]}'''),
            ),
          ),
        );
        verifyInOrder([
          () => codePushClientWrapper.createApp(
            appName: '$appName (development)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (developmentInternal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (production)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (productionInternal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (staging)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (stagingInternal)',
            organizationId: organizationId,
          ),
        ]);
      });

      test('ios only', () async {
        final appIds = [
          'test-appId-1',
          'test-appId-2',
          'test-appId-3',
          'test-appId-4',
          'test-appId-5',
          'test-appId-6',
        ];
        var index = 0;
        when(() => apple.flavors(platform: ApplePlatform.ios)).thenReturn({
          'development',
          'developmentInternal',
          'production',
          'productionInternal',
          'staging',
          'stagingInternal',
        });
        when(
          () => codePushClientWrapper.createApp(
            appName: any(named: 'appName'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((invocation) async {
          final appName = invocation.namedArguments[#appName] as String?;
          return App(id: appIds[index++], displayName: appName ?? '-');
        });
        when(
          () => gradlew.productFlavors(any()),
        ).thenThrow(const MissingAndroidProjectException(''));
        await runWithOverrides(command.run);
        verify(
          () => shorebirdYamlFile.writeAsStringSync(
            any(
              that: contains('''
app_id: ${appIds[0]}
flavors:
  development: ${appIds[0]}
  developmentInternal: ${appIds[1]}
  production: ${appIds[2]}
  productionInternal: ${appIds[3]}
  staging: ${appIds[4]}
  stagingInternal: ${appIds[5]}'''),
            ),
          ),
        );
        verifyInOrder([
          () => codePushClientWrapper.createApp(
            appName: '$appName (development)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (developmentInternal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (production)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (productionInternal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (staging)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (stagingInternal)',
            organizationId: organizationId,
          ),
        ]);
      });

      test('ios w/flavors and android w/out flavors', () async {
        final appIds = [
          'test-appId-1',
          'test-appId-2',
          'test-appId-3',
          'test-appId-4',
          'test-appId-5',
          'test-appId-6',
          'test-appId-7',
        ];
        var index = 0;
        when(() => apple.flavors(platform: ApplePlatform.ios)).thenReturn({
          'development',
          'developmentInternal',
          'production',
          'productionInternal',
          'staging',
          'stagingInternal',
        });
        when(() => gradlew.productFlavors(any())).thenAnswer((_) async => {});
        when(
          () => codePushClientWrapper.createApp(
            appName: any(named: 'appName'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((invocation) async {
          final appName = invocation.namedArguments[#appName] as String?;
          return App(id: appIds[index++], displayName: appName ?? '--');
        });
        await runWithOverrides(command.run);
        verify(
          () => shorebirdYamlFile.writeAsStringSync(
            any(
              that: contains('''
app_id: ${appIds[0]}
flavors:
  development: ${appIds[1]}
  developmentInternal: ${appIds[2]}
  production: ${appIds[3]}
  productionInternal: ${appIds[4]}
  staging: ${appIds[5]}
  stagingInternal: ${appIds[6]}'''),
            ),
          ),
        );
        verifyInOrder([
          () => codePushClientWrapper.createApp(
            appName: '$appName (development)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (developmentInternal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (production)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (productionInternal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (staging)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (stagingInternal)',
            organizationId: organizationId,
          ),
        ]);
      });

      test('android w/flavors and ios w/out flavors', () async {
        final appIds = [
          'test-appId-1',
          'test-appId-2',
          'test-appId-3',
          'test-appId-4',
          'test-appId-5',
          'test-appId-6',
          'test-appId-7',
        ];
        var index = 0;
        when(() => apple.flavors(platform: ApplePlatform.ios)).thenReturn({});
        when(() => gradlew.productFlavors(any())).thenAnswer(
          (_) async => {
            'development',
            'developmentInternal',
            'production',
            'productionInternal',
            'staging',
            'stagingInternal',
          },
        );
        when(
          () => codePushClientWrapper.createApp(
            appName: any(named: 'appName'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((invocation) async {
          final appName = invocation.namedArguments[#appName] as String?;
          return App(id: appIds[index++], displayName: appName ?? '-');
        });
        await runWithOverrides(command.run);
        verify(
          () => shorebirdYamlFile.writeAsStringSync(
            any(
              that: contains('''
app_id: ${appIds[0]}
flavors:
  development: ${appIds[1]}
  developmentInternal: ${appIds[2]}
  production: ${appIds[3]}
  productionInternal: ${appIds[4]}
  staging: ${appIds[5]}
  stagingInternal: ${appIds[6]}'''),
            ),
          ),
        );
        verifyInOrder([
          () => codePushClientWrapper.createApp(
            appName: '$appName (development)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (developmentInternal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (production)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (productionInternal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (staging)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (stagingInternal)',
            organizationId: organizationId,
          ),
        ]);
      });

      test('ios + android w/same variants', () async {
        final appIds = [
          'test-appId-1',
          'test-appId-2',
          'test-appId-3',
          'test-appId-4',
          'test-appId-5',
          'test-appId-6',
        ];
        const variants = {
          'development',
          'developmentInternal',
          'production',
          'productionInternal',
          'staging',
          'stagingInternal',
        };
        var index = 0;
        when(
          () => gradlew.productFlavors(any()),
        ).thenAnswer((_) async => variants);
        when(
          () => apple.flavors(platform: ApplePlatform.ios),
        ).thenReturn(variants);
        when(
          () => codePushClientWrapper.createApp(
            appName: any(named: 'appName'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((invocation) async {
          final appName = invocation.namedArguments[#appName] as String?;
          return App(id: appIds[index++], displayName: appName ?? '-');
        });
        await runWithOverrides(command.run);
        verify(
          () => shorebirdYamlFile.writeAsStringSync(
            any(
              that: contains('''
app_id: ${appIds[0]}
flavors:
  development: ${appIds[0]}
  developmentInternal: ${appIds[1]}
  production: ${appIds[2]}
  productionInternal: ${appIds[3]}
  staging: ${appIds[4]}
  stagingInternal: ${appIds[5]}'''),
            ),
          ),
        );
        verifyInOrder([
          () => codePushClientWrapper.createApp(
            appName: '$appName (development)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (developmentInternal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (production)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (productionInternal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (staging)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (stagingInternal)',
            organizationId: organizationId,
          ),
        ]);
      });

      test('multiple platforms w/different variants', () async {
        final appIds = [
          'test-appId-1',
          'test-appId-2',
          'test-appId-3',
          'test-appId-4',
          'test-appId-5',
          'test-appId-6',
          'test-appId-7',
          'test-appId-8',
          'test-appId-9',
        ];
        const androidVariants = {
          'dev',
          'devInternal',
          'production',
          'productionInternal',
        };
        const iosVariants = {
          'development',
          'developmentInternal',
          'production',
          'productionInternal',
          'staging',
          'stagingInternal',
        };
        const macosVariants = {
          'development',
          'developmentInternal',
          'production-macos',
        };
        var index = 0;
        when(
          () => gradlew.productFlavors(any()),
        ).thenAnswer((_) async => androidVariants);
        when(
          () => apple.flavors(platform: ApplePlatform.ios),
        ).thenReturn(iosVariants);
        when(
          () => apple.flavors(platform: ApplePlatform.macos),
        ).thenReturn(macosVariants);
        when(
          () => codePushClientWrapper.createApp(
            appName: any(named: 'appName'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((invocation) async {
          final appName = invocation.namedArguments[#appName] as String?;
          return App(id: appIds[index++], displayName: appName ?? '-');
        });
        await runWithOverrides(command.run);
        verify(
          () => shorebirdYamlFile.writeAsStringSync(
            any(
              that: contains('''
app_id: test-appId-1
flavors:
  dev: test-appId-1
  devInternal: test-appId-2
  production: test-appId-3
  productionInternal: test-appId-4
  development: test-appId-5
  developmentInternal: test-appId-6
  staging: test-appId-7
  stagingInternal: test-appId-8
  production-macos: test-appId-9'''),
            ),
          ),
        );
        verifyInOrder([
          () => codePushClientWrapper.createApp(
            appName: '$appName (dev)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (devInternal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (production)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (productionInternal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (development)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (developmentInternal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (staging)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (stagingInternal)',
            organizationId: organizationId,
          ),
          () => codePushClientWrapper.createApp(
            appName: '$appName (production-macos)',
            organizationId: organizationId,
          ),
        ]);
      });

      group('with new flavors added', () {
        final existingFlavors = {'a': 'test-appId-1', 'b': 'test-appId-2'};

        setUp(() {
          const androidVariants = {'a', 'b', 'c', 'd'};
          when(
            () => gradlew.productFlavors(any()),
          ).thenAnswer((_) async => androidVariants);

          when(() => shorebirdEnv.hasShorebirdYaml).thenReturn(true);
          when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
          when(() => shorebirdYaml.appId).thenReturn(appId);
          when(() => shorebirdYaml.flavors).thenReturn(existingFlavors);
        });

        test(
          'exits with software error if retrieving existing app fails',
          () async {
            when(
              () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
            ).thenThrow(Exception('oh no'));
            final result = await runWithOverrides(command.run);
            expect(result, ExitCode.software.code);
          },
        );

        test('creates new flavor entries in shorebird.yaml', () async {
          const newAppIds = ['test-appId-3', 'test-appId-4'];
          const appName = 'my-app';
          var index = 0;

          when(
            () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
          ).thenAnswer(
            (_) async => AppMetadata(
              appId: appId,
              displayName: appName,
              createdAt: DateTime(2023),
              updatedAt: DateTime(2023),
            ),
          );
          when(
            () => codePushClientWrapper.createApp(
              appName: any(named: 'appName'),
              organizationId: any(named: 'organizationId'),
            ),
          ).thenAnswer((invocation) async {
            final appName = invocation.namedArguments[#appName] as String?;
            return App(id: newAppIds[index++], displayName: appName ?? '-');
          });

          await runWithOverrides(command.run);

          verify(() => logger.info('New flavors detected: c, d')).called(1);
          verifyNever(
            () => codePushClientWrapper.createApp(
              appName: '$appName (a)',
              organizationId: organizationId,
            ),
          );
          verifyNever(
            () => codePushClientWrapper.createApp(
              appName: '$appName (b)',
              organizationId: organizationId,
            ),
          );
          verify(
            () => codePushClientWrapper.createApp(
              appName: '$appName (c)',
              organizationId: organizationId,
            ),
          ).called(1);
          verify(
            () => codePushClientWrapper.createApp(
              appName: '$appName (d)',
              organizationId: organizationId,
            ),
          ).called(1);
          verify(
            () => shorebirdYamlFile.writeAsStringSync(
              any(
                that: contains('''
app_id: test_app_id
flavors:
  a: test-appId-1
  b: test-appId-2
  c: test-appId-3
  d: test-appId-4'''),
              ),
            ),
          ).called(1);
        });
      });
    });

    test('detects existing shorebird.yaml in pubspec.yaml assets', () async {
      when(() => pubspecYamlFile.readAsStringSync()).thenReturn('''
$pubspecYamlContent
flutter:
  assets:
    - shorebird.yaml
''');
      await runWithOverrides(command.run);
      verify(
        () => shorebirdYamlFile.writeAsStringSync(
          any(that: contains('app_id: $appId')),
        ),
      );
    });

    test('logs success message on completion', () async {
      await runWithOverrides(command.run);
      verify(
        () => logger.info(
          any(
            that: stringContainsInOrder([
              lightGreen.wrap('🐦 Shorebird initialized successfully!')!,
              '✅ A shorebird app has been created.',
              '✅ A "shorebird.yaml" has been created.',
              '''✅ The "pubspec.yaml" has been updated to include "shorebird.yaml" as an asset.''',
              '''📦 To create a new release use: "${lightCyan.wrap('shorebird release')}".''',
              '''🚀 To push an update use: "${lightCyan.wrap('shorebird patch')}".''',
              '''👀 To preview a release use: "${lightCyan.wrap('shorebird preview')}".''',
              '''For more information about Shorebird, visit ${link(uri: Uri.parse('https://shorebird.dev'))}''',
              '',
            ]),
          ),
        ),
      ).called(1);
    });

    test('ensures that addShorebirdYamlToPubspecAssets is called', () async {
      when(() => shorebirdEnv.pubspecContainsShorebirdYaml).thenReturn(false);
      await runWithOverrides(command.run);
      verify(pubspecEditor.addShorebirdYamlToPubspecAssets).called(1);
    });

    test('fixes fixable validation errors', () async {
      await runWithOverrides(command.run);
      verifyInOrder([
        () => logger.info(
          any(
            that: contains(
              lightGreen.wrap('🐦 Shorebird initialized successfully!'),
            ),
          ),
        ),
        () => doctor.runValidators(any(), applyFixes: true),
      ]);
    });
  });
}

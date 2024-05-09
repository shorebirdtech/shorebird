import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/ios_framework_releaser.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(
    IosFrameworkReleaser,
    () {
      late ArgResults argResults;
      late ArtifactBuilder artifactBuilder;
      late ArtifactManager artifactManager;
      late CodePushClientWrapper codePushClientWrapper;
      late Doctor doctor;
      late Platform platform;
      late Directory projectRoot;
      late ShorebirdLogger logger;
      late OperatingSystemInterface operatingSystemInterface;
      late Progress progress;
      late ShorebirdFlutterValidator flutterValidator;
      late ShorebirdProcess shorebirdProcess;
      late ShorebirdEnv shorebirdEnv;
      late ShorebirdFlutter shorebirdFlutter;
      late ShorebirdValidator shorebirdValidator;
      late XcodeBuild xcodeBuild;
      late IosFrameworkReleaser iosFrameworkReleaser;

      R runWithOverrides<R>(R Function() body) {
        return runScoped(
          body,
          values: {
            artifactBuilderRef.overrideWith(() => artifactBuilder),
            artifactManagerRef.overrideWith(() => artifactManager),
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
            doctorRef.overrideWith(() => doctor),
            loggerRef.overrideWith(() => logger),
            osInterfaceRef.overrideWith(() => operatingSystemInterface),
            platformRef.overrideWith(() => platform),
            processRef.overrideWith(() => shorebirdProcess),
            shorebirdEnvRef.overrideWith(() => shorebirdEnv),
            shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
            shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            xcodeBuildRef.overrideWith(() => xcodeBuild),
          },
        );
      }

      setUpAll(() {
        registerFallbackValue(Directory(''));
        registerFallbackValue(ReleasePlatform.ios);
        setExitFunctionForTests();
      });

      tearDownAll(restoreExitFunction);

      setUp(() {
        argResults = MockArgResults();
        artifactBuilder = MockArtifactBuilder();
        artifactManager = MockArtifactManager();
        codePushClientWrapper = MockCodePushClientWrapper();
        doctor = MockDoctor();
        operatingSystemInterface = MockOperatingSystemInterface();
        platform = MockPlatform();
        progress = MockProgress();
        projectRoot = Directory.systemTemp.createTempSync();
        logger = MockShorebirdLogger();
        shorebirdProcess = MockShorebirdProcess();
        shorebirdEnv = MockShorebirdEnv();
        flutterValidator = MockShorebirdFlutterValidator();
        shorebirdFlutter = MockShorebirdFlutter();
        shorebirdValidator = MockShorebirdValidator();
        xcodeBuild = MockXcodeBuild();

        when(() => logger.progress(any())).thenReturn(progress);

        when(
          () => shorebirdEnv.getShorebirdProjectRoot(),
        ).thenReturn(projectRoot);

        iosFrameworkReleaser = IosFrameworkReleaser(
          argResults: argResults,
          flavor: null,
          target: null,
        );
      });

      group('requiresReleaseVersionArg', () {
        test('is true', () {
          expect(iosFrameworkReleaser.requiresReleaseVersionArg, isTrue);
        });
      });

      group('releaseType', () {
        test('is xcframework', () {
          expect(iosFrameworkReleaser.releaseType, ReleaseType.iosFramework);
        });
      });

      group('assertArgsAreValid', () {
        group('when split-per-abi is true', () {
          setUp(() {
            when(() => argResults.wasParsed('release-version'))
                .thenReturn(false);
          });

          test('exits with code 64', () async {
            await expectLater(
              () => runWithOverrides(iosFrameworkReleaser.assertArgsAreValid),
              exitsWithCode(ExitCode.usage),
            );
          });
        });

        group('when arguments are valid', () {
          setUp(() {
            when(
              () => argResults.wasParsed('release-version'),
            ).thenReturn(true);
          });

          test('returns normally', () {
            expect(
              () => runWithOverrides(iosFrameworkReleaser.assertArgsAreValid),
              returnsNormally,
            );
          });
        });
      });

      group('assertPreconditions', () {
        setUp(() {
          when(
            () => doctor.iosCommandValidators,
          ).thenReturn([flutterValidator]);
          when(flutterValidator.validate).thenAnswer((_) async => []);
        });

        group('when validation succeeds', () {
          setUp(() {
            when(
              () => shorebirdValidator.validatePreconditions(
                checkUserIsAuthenticated: any(
                  named: 'checkUserIsAuthenticated',
                ),
                checkShorebirdInitialized: any(
                  named: 'checkShorebirdInitialized',
                ),
                validators: any(named: 'validators'),
                supportedOperatingSystems: any(
                  named: 'supportedOperatingSystems',
                ),
              ),
            ).thenAnswer((_) async {});
          });

          test('returns normally', () async {
            await expectLater(
              () => runWithOverrides(iosFrameworkReleaser.assertPreconditions),
              returnsNormally,
            );
          });
        });

        group('when validation fails', () {
          final exception = ValidationFailedException();

          setUp(() {
            when(
              () => shorebirdValidator.validatePreconditions(
                checkUserIsAuthenticated: any(
                  named: 'checkUserIsAuthenticated',
                ),
                checkShorebirdInitialized: any(
                  named: 'checkShorebirdInitialized',
                ),
                validators: any(named: 'validators'),
                supportedOperatingSystems: any(
                  named: 'supportedOperatingSystems',
                ),
              ),
            ).thenThrow(exception);
          });

          test('exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(iosFrameworkReleaser.assertPreconditions),
              exitsWithCode(exception.exitCode),
            );
            verify(
              () => shorebirdValidator.validatePreconditions(
                checkUserIsAuthenticated: true,
                checkShorebirdInitialized: true,
                validators: [flutterValidator],
                supportedOperatingSystems: {Platform.macOS},
              ),
            ).called(1);
          });
        });
      });

      group('buildReleaseArtifacts', () {
        const flutterVersionAndRevision = '3.10.6 (83305b5088)';

        void setUpProjectRootArtifacts() {
          // Create an xcframework in the release directory to simulate running
          // this command a subsequent time.
          Directory(p.join(projectRoot.path, 'release', 'Flutter.xcframework'))
              .createSync(recursive: true);
          Directory(
            p.join(
              projectRoot.path,
              'build',
              'ios',
              'framework',
              'Release',
              'Flutter.xcframework',
            ),
          ).createSync(recursive: true);
        }

        setUp(() {
          when(
            () => artifactBuilder.buildIosFramework(),
          ).thenAnswer(
            (_) async => File(''),
          );
          when(() => artifactManager.getAppXcframeworkDirectory()).thenReturn(
            Directory(
              p.join(
                projectRoot.path,
                'build',
                'ios',
                'framework',
                'Release',
              ),
            ),
          );
          when(
            () => shorebirdFlutter.getVersionAndRevision(),
          ).thenAnswer((_) async => flutterVersionAndRevision);

          setUpProjectRootArtifacts();
        });

        group('when build succeeds', () {
          test('produces xcframework in release directory', () async {
            final xcframework = await runWithOverrides(
              iosFrameworkReleaser.buildReleaseArtifacts,
            );

            expect(xcframework.path, p.join(projectRoot.path, 'release'));
            verify(artifactBuilder.buildIosFramework).called(1);
          });
        });

        group('when build fails', () {
          setUp(() {
            when(
              () => artifactBuilder.buildIosFramework(),
            ).thenThrow(Exception('build failed'));
          });

          test('logs error and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(
                iosFrameworkReleaser.buildReleaseArtifacts,
              ),
              exitsWithCode(ExitCode.software),
            );
            verify(
              () => progress.fail(
                'Failed to build iOS framework: Exception: build failed',
              ),
            ).called(1);
          });
        });
      });

      group('getReleaseVersion', () {
        const releaseVersion = '1.0.0';
        setUp(() {
          when(() => argResults['release-version']).thenReturn(releaseVersion);
        });

        test('returns value from argResults', () async {
          final result = await runWithOverrides(
            () => iosFrameworkReleaser.getReleaseVersion(
              releaseArtifactRoot: Directory(''),
            ),
          );
          expect(result, releaseVersion);
        });
      });

      group('uploadReleaseArtifacts', () {
        const releaseVersion = '1.0.0';
        const appId = 'appId';
        const flutterRevision = 'deadbeef';

        final release = Release(
          id: 42,
          appId: appId,
          version: releaseVersion,
          flutterRevision: flutterRevision,
          displayName: '1.2.3+1',
          platformStatuses: {},
          createdAt: DateTime(2023),
          updatedAt: DateTime(2023),
        );

        setUp(() {
          when(
            () => codePushClientWrapper.createIosFrameworkReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              appFrameworkPath: any(named: 'appFrameworkPath'),
            ),
          ).thenAnswer((_) async {});
        });

        test('uploads artifacts', () async {
          await runWithOverrides(
            () => iosFrameworkReleaser.uploadReleaseArtifacts(
              release: release,
              appId: appId,
            ),
          );

          verify(
            () => codePushClientWrapper.createIosFrameworkReleaseArtifacts(
              appId: appId,
              releaseId: release.id,
              appFrameworkPath: p.join(
                projectRoot.path,
                'release',
                ArtifactManager.appXcframeworkName,
              ),
            ),
          ).called(1);
        });
      });

      group('releaseMetadata', () {
        const operatingSystem = 'macos';
        const operatingSystemVersion = '11.0.0';
        const xcodeVersion = '123';

        setUp(() {
          when(() => platform.operatingSystem).thenReturn(operatingSystem);
          when(() => platform.operatingSystemVersion)
              .thenReturn(operatingSystemVersion);
          when(() => xcodeBuild.version())
              .thenAnswer((_) async => xcodeVersion);
        });

        test('returns expected metadata', () async {
          expect(
            await runWithOverrides(iosFrameworkReleaser.releaseMetadata),
            equals(
              const UpdateReleaseMetadata(
                releasePlatform: ReleasePlatform.ios,
                flutterVersionOverride: null,
                generatedApks: false,
                environment: BuildEnvironmentMetadata(
                  operatingSystem: operatingSystem,
                  operatingSystemVersion: operatingSystemVersion,
                  shorebirdVersion: packageVersion,
                  xcodeVersion: xcodeVersion,
                ),
              ),
            ),
          );
        });
      });

      group('postReleaseInstructions', () {
        test('returns expected instructions', () {
          final relativeFrameworkDirectoryPath = p.relative(
            p.join(projectRoot.path, 'release'),
          );
          expect(
            runWithOverrides(
              () => iosFrameworkReleaser.postReleaseInstructions,
            ),
            equals('''

Your next step is to add the .xcframework files found in the ${lightCyan.wrap(relativeFrameworkDirectoryPath)} directory to your iOS app.

To do this:
    1. Add the relative path to the ${lightCyan.wrap(relativeFrameworkDirectoryPath)} directory to your app's Framework Search Paths in your Xcode build settings.
    2. Embed the App.xcframework and ShorebirdFlutter.framework in your Xcode project.

Instructions for these steps can be found at https://docs.flutter.dev/add-to-app/ios/project-setup#option-b---embed-frameworks-in-xcode.
'''),
          );
        });
      });
    },
    testOn: 'mac-os',
  );
}

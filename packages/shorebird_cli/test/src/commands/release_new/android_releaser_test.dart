import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release_new/android_releaser.dart';
import 'package:shorebird_cli/src/commands/release_new/release_type.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
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
  group(AndroidReleaser, () {
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late CodePushClientWrapper codePushClientWrapper;
    late Doctor doctor;
    late Platform platform;
    late Directory projectRoot;
    late Logger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late Progress progress;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdAndroidArtifacts shorebirdAndroidArtifacts;
    late AndroidReleaser androidReleaser;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          shorebirdAndroidArtifactsRef
              .overrideWith(() => shorebirdAndroidArtifacts),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(ReleasePlatform.android);
      setExitFunctionForTests();
    });

    tearDownAll(restoreExitFunction);

    setUp(() {
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      codePushClientWrapper = MockCodePushClientWrapper();
      doctor = MockDoctor();
      operatingSystemInterface = MockOperatingSystemInterface();
      platform = MockPlatform();
      progress = MockProgress();
      projectRoot = Directory.systemTemp.createTempSync();
      logger = MockLogger();
      flutterValidator = MockShorebirdFlutterValidator();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();
      shorebirdAndroidArtifacts = MockShorebirdAndroidArtifacts();

      when(() => argResults['target-platform'])
          .thenReturn(Arch.values.map((a) => a.targetPlatformCliArg).toList());

      when(() => doctor.androidCommandValidators)
          .thenReturn([flutterValidator]);
      when(flutterValidator.validate).thenAnswer((_) async => []);

      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);

      androidReleaser = AndroidReleaser(
        argResults: argResults,
        flavor: null,
        target: null,
      );
    });

    group('releaseType', () {
      test('is android', () {
        expect(androidReleaser.releaseType, ReleaseType.android);
      });
    });

    group('assertPreconditions', () {
      group('when validation succeeds', () {
        setUp(() {
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
              checkShorebirdInitialized:
                  any(named: 'checkShorebirdInitialized'),
              validators: any(named: 'validators'),
              supportedOperatingSystems:
                  any(named: 'supportedOperatingSystems'),
            ),
          ).thenAnswer((_) async {});
        });

        test('returns normally', () async {
          await expectLater(
            () => runWithOverrides(androidReleaser.assertPreconditions),
            returnsNormally,
          );
        });
      });

      group('when validation fails', () {
        setUp(() {
          final exception = ValidationFailedException();
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
              checkShorebirdInitialized:
                  any(named: 'checkShorebirdInitialized'),
              validators: any(named: 'validators'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final exception = ValidationFailedException();
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
              checkShorebirdInitialized:
                  any(named: 'checkShorebirdInitialized'),
              validators: any(named: 'validators'),
            ),
          ).thenThrow(exception);
          await expectLater(
            () => runWithOverrides(androidReleaser.assertPreconditions),
            exitsWithCode(exception.exitCode),
          );
          verify(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: true,
              checkShorebirdInitialized: true,
              validators: [flutterValidator],
            ),
          ).called(1);
        });
      });
    });

    group('assertArgsAreValid', () {
      group('when split-per-abi is true', () {
        setUp(() {
          when(() => argResults['android-artifact']).thenReturn('apk');
          when(() => argResults['split-per-abi']).thenReturn(true);
        });

        test('exits with code 69', () async {
          await expectLater(
            () => runWithOverrides(androidReleaser.assertArgsAreValid),
            exitsWithCode(ExitCode.unavailable),
          );
        });
      });

      group('when arguments are valid', () {
        setUp(() {
          when(() => argResults['android-artifact']).thenReturn('apk');
          when(() => argResults['split-per-abi']).thenReturn(false);
        });

        test('returns normally', () {
          expect(
            () => runWithOverrides(androidReleaser.assertArgsAreValid),
            returnsNormally,
          );
        });
      });
    });

    group('buildReleaseArtifacts', () {
      const flutterVersionAndRevision = '3.10.6 (83305b5088)';
      late File aabFile;

      setUp(() {
        aabFile = File('');
        when(() => argResults['android-artifact']).thenReturn('aab');
        when(
          () => artifactBuilder.buildAppBundle(
            flavor: any(named: 'flavor'),
            target: any(named: 'target'),
            targetPlatforms: any(named: 'targetPlatforms'),
          ),
        ).thenAnswer((_) async => aabFile);
        when(
          () => artifactBuilder.buildApk(
            flavor: any(named: 'flavor'),
            target: any(named: 'target'),
            targetPlatforms: any(named: 'targetPlatforms'),
          ),
        ).thenAnswer(
          (_) async => File(''),
        );
        when(
          () => shorebirdFlutter.getVersionAndRevision(),
        ).thenAnswer((_) async => flutterVersionAndRevision);
        when(
          () => shorebirdAndroidArtifacts.findAab(
            project: any(named: 'project'),
            flavor: any(named: 'flavor'),
          ),
        ).thenReturn(aabFile);
      });

      group('when aab build fails', () {
        setUp(() {
          when(
            () => artifactBuilder.buildAppBundle(
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
              targetPlatforms: any(named: 'targetPlatforms'),
            ),
          ).thenThrow(ArtifactBuildException('Uh oh'));
        });

        test('logs error and exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(androidReleaser.buildReleaseArtifacts),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail('Uh oh')).called(1);
        });
      });

      group('when building apk', () {
        setUp(() {
          when(() => argResults['android-artifact']).thenReturn('apk');
        });

        group('when apk build fails', () {
          setUp(() {
            when(
              () => artifactBuilder.buildApk(
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
                targetPlatforms: any(named: 'targetPlatforms'),
              ),
            ).thenThrow(ArtifactBuildException('Uh oh'));
          });

          test('logs error and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(androidReleaser.buildReleaseArtifacts),
              exitsWithCode(ExitCode.software),
            );
            verify(() => progress.fail('Uh oh')).called(1);
          });
        });
      });

      group('when the build succeeds', () {
        test('returns the path to the aab', () async {
          final result = await runWithOverrides(
            () => androidReleaser.buildReleaseArtifacts(),
          );
          expect(result, aabFile);
          verify(
            () => artifactBuilder.buildAppBundle(targetPlatforms: Arch.values),
          ).called(1);
        });

        test('does not built apk by default', () async {
          await runWithOverrides(
            () => androidReleaser.buildReleaseArtifacts(),
          );
          verifyNever(
            () => artifactBuilder.buildApk(
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
              targetPlatforms: any(named: 'targetPlatforms'),
            ),
          );
        });
      });

      group('with flavor and target', () {
        const flavor = 'my-flavor';
        const target = 'my-target';

        setUp(() {
          when(() => argResults['android-artifact']).thenReturn('apk');
          androidReleaser = AndroidReleaser(
            argResults: argResults,
            flavor: flavor,
            target: target,
          );
        });

        test('builds artifacts with flavor and target', () async {
          await runWithOverrides(() => androidReleaser.buildReleaseArtifacts());
          verify(
            () => artifactBuilder.buildAppBundle(
              flavor: flavor,
              target: target,
              targetPlatforms: Arch.values,
            ),
          ).called(1);
          verify(
            () => artifactBuilder.buildApk(
              flavor: flavor,
              target: target,
              targetPlatforms: Arch.values,
            ),
          ).called(1);
        });
      });
    });

    group('getReleaseVersion', () {
      const releaseVersion = '1.0.0';
      setUp(() {
        when(
          () => shorebirdAndroidArtifacts.extractReleaseVersionFromAppBundle(
            any(),
          ),
        ).thenAnswer((_) async => releaseVersion);
      });

      test('returns value from artifactManager', () async {
        final result = await runWithOverrides(
          () => androidReleaser.getReleaseVersion(
            releaseArtifactRoot: Directory(''),
          ),
        );
        expect(result, releaseVersion);
        verify(
          () =>
              shorebirdAndroidArtifacts.extractReleaseVersionFromAppBundle(''),
        ).called(1);
      });

      group('when artifactManager throws exception', () {
        setUp(() {
          when(
            () => shorebirdAndroidArtifacts.extractReleaseVersionFromAppBundle(
              any(),
            ),
          ).thenThrow(Exception('oops'));
        });

        test('logs error and exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(
              () => androidReleaser.getReleaseVersion(
                releaseArtifactRoot: Directory(''),
              ),
            ),
            exitsWithCode(ExitCode.software),
          );
          verify(() => progress.fail('Exception: oops')).called(1);
        });
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

      late File aabFile;

      setUp(() {
        aabFile = File(p.join(projectRoot.path, 'app.aab'))..createSync();

        when(
          () => codePushClientWrapper.createAndroidReleaseArtifacts(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            projectRoot: any(named: 'projectRoot'),
            aabPath: any(named: 'aabPath'),
            platform: any(named: 'platform'),
            architectures: any(named: 'architectures'),
            flavor: any(named: 'flavor'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => shorebirdAndroidArtifacts.findAab(
            project: any(named: 'project'),
            flavor: any(named: 'flavor'),
          ),
        ).thenReturn(aabFile);
      });

      test('calls codePushClientWrapper.createAndroidReleaseArtifacts',
          () async {
        await runWithOverrides(
          () => androidReleaser.uploadReleaseArtifacts(
            appId: appId,
            release: release,
          ),
        );
        verify(
          () => codePushClientWrapper.createAndroidReleaseArtifacts(
            appId: appId,
            releaseId: release.id,
            projectRoot: projectRoot.path,
            aabPath: aabFile.path,
            platform: ReleasePlatform.android,
            architectures: Arch.values,
            flavor: androidReleaser.flavor,
          ),
        ).called(1);
      });
    });

    group('releaseMetadata', () {
      const operatingSystem = 'macos';
      const operatingSystemVersion = '11.0.0';

      setUp(() {
        when(() => platform.operatingSystem).thenReturn(operatingSystem);
        when(() => platform.operatingSystemVersion)
            .thenReturn(operatingSystemVersion);
      });

      group('when an apk is generated', () {
        setUp(() {
          when(() => argResults['android-artifact']).thenReturn('apk');
        });

        test('returns expected metadata', () {
          expect(
            runWithOverrides(() => androidReleaser.releaseMetadata),
            const UpdateReleaseMetadata(
              releasePlatform: ReleasePlatform.android,
              flutterVersionOverride: null,
              generatedApks: true,
              environment: BuildEnvironmentMetadata(
                operatingSystem: operatingSystem,
                operatingSystemVersion: operatingSystemVersion,
                shorebirdVersion: packageVersion,
                xcodeVersion: null,
              ),
            ),
          );
        });
      });

      group('when no apk is generated', () {
        setUp(() {
          when(() => argResults['android-artifact']).thenReturn('aab');
        });

        test('returns expected metadata', () {
          expect(
            runWithOverrides(() => androidReleaser.releaseMetadata),
            const UpdateReleaseMetadata(
              releasePlatform: ReleasePlatform.android,
              flutterVersionOverride: null,
              generatedApks: false,
              environment: BuildEnvironmentMetadata(
                operatingSystem: operatingSystem,
                operatingSystemVersion: operatingSystemVersion,
                shorebirdVersion: packageVersion,
                xcodeVersion: null,
              ),
            ),
          );
        });
      });
    });

    group('postReleaseInstructions', () {
      const apkPath = 'path/to/app.apk';
      const aabPath = 'path/to/app.aab';

      setUp(() {
        when(
          () => shorebirdAndroidArtifacts.findApk(
            project: any(named: 'project'),
            flavor: any(named: 'flavor'),
          ),
        ).thenReturn(File(apkPath));
        when(
          () => shorebirdAndroidArtifacts.findAab(
            project: any(named: 'project'),
            flavor: any(named: 'flavor'),
          ),
        ).thenReturn(File(aabPath));
      });

      group('when an apk is generated', () {
        setUp(() {
          when(() => argResults['android-artifact']).thenReturn('apk');
        });

        test('returns expected instructions', () {
          expect(
            runWithOverrides(() => androidReleaser.postReleaseInstructions),
            '''
Your next step is to upload the app bundle to the Play Store:
${lightCyan.wrap(aabPath)}

Or distribute the apk:
${lightCyan.wrap(apkPath)}

For information on uploading to the Play Store, see:
${link(uri: Uri.parse('https://support.google.com/googleplay/android-developer/answer/9859152?hl=en'))}
''',
          );
        });
      });

      group('when no apk is generated', () {
        setUp(() {
          when(() => argResults['android-artifact']).thenReturn('aab');
        });

        test('returns expected instructions', () {
          expect(
            runWithOverrides(() => androidReleaser.postReleaseInstructions),
            '''
Your next step is to upload the app bundle to the Play Store:
${lightCyan.wrap(aabPath)}

For information on uploading to the Play Store, see:
${link(uri: Uri.parse('https://support.google.com/googleplay/android-developer/answer/9859152?hl=en'))}
''',
          );
        });
      });
    });
  });
}

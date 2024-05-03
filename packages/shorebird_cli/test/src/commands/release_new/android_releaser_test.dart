import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
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
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(AndroidReleaser, () {
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late ArtifactManager artifactManager;
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
          artifactManagerRef.overrideWith(() => artifactManager),
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
      artifactManager = MockArtifactManager();
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

    group('validatePreconditions', () {
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
            () => runWithOverrides(androidReleaser.validatePreconditions),
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
            () => runWithOverrides(androidReleaser.validatePreconditions),
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

    group('validateArgs', () {
      group('when split-per-abi is true', () {
        setUp(() {
          when(() => argResults['android-artifact']).thenReturn('apk');
          when(() => argResults['split-per-abi']).thenReturn(true);
        });

        test('exits with code 69', () async {
          await expectLater(
            () => runWithOverrides(androidReleaser.validateArgs),
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
            () => runWithOverrides(androidReleaser.validateArgs),
            returnsNormally,
          );
        });
      });
    });

    group('buildReleaseArtifacts', () {
      const flutterVersionAndRevision = '3.10.6 (83305b5088)';

      setUp(() {
        when(() => argResults['android-artifact']).thenReturn('apk');
        when(
          () => artifactBuilder.buildAppBundle(
            flavor: any(named: 'flavor'),
            target: any(named: 'target'),
            targetPlatforms: any(named: 'targetPlatforms'),
          ),
        ).thenAnswer(
          (_) async => File(''),
        );
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
      });

      test('errors when the app bundle cannot be found', () async {
        when(
          () => shorebirdAndroidArtifacts.findAab(
            project: any(named: 'project'),
            flavor: any(named: 'flavor'),
          ),
        ).thenThrow(
          ArtifactNotFoundException(
            artifactName: 'app-release.aab',
            buildDir: 'buildDir',
          ),
        );
        await expectLater(
          () => runWithOverrides(androidReleaser.buildReleaseArtifacts),
          exitsWithCode(ExitCode.software),
        );
        verify(
          () => logger.err(
            'Build succeeded, but could not find the AAB in the build '
            'directory. Expected to find app-release.aab',
          ),
        ).called(1);
      });

      test('errors when multiple aabs are found', () async {
        shorebirdAndroidArtifacts = MockShorebirdAndroidArtifacts();
        when(
          () => shorebirdAndroidArtifacts.findAab(
            project: any(named: 'project'),
            flavor: any(named: 'flavor'),
          ),
        ).thenThrow(
          MultipleArtifactsFoundException(
            foundArtifacts: [File('a'), File('b')],
            buildDir: 'buildDir',
          ),
        );
        await expectLater(
          () => runWithOverrides(androidReleaser.buildReleaseArtifacts),
          exitsWithCode(ExitCode.software),
        );
        verify(
          () => logger.err(
            'Build succeeded, but it generated multiple AABs in the build '
            'directory. (a, b)',
          ),
        ).called(1);
      });
    });

    group('getReleaseVersion', () {
      const releaseVersion = '1.0.0';
      setUp(() {
        when(() => artifactManager.extractReleaseVersionFromAppBundle(any()))
            .thenAnswer((_) async => releaseVersion);
      });

      test('returns value from artifactManager', () async {
        final result = await runWithOverrides(
          () => androidReleaser.getReleaseVersion(
            releaseArtifactRoot: Directory(''),
          ),
        );
        expect(result, releaseVersion);
        verify(
          () => artifactManager.extractReleaseVersionFromAppBundle(''),
        ).called(1);
      });

      group('when artifactManager throws exception', () {
        setUp(() {
          when(() => artifactManager.extractReleaseVersionFromAppBundle(any()))
              .thenThrow(Exception('oops'));
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
  });
}

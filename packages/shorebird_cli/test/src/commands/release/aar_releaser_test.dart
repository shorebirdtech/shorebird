import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/aar_releaser.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(AarReleaser, () {
    const packageName = 'com.example.my_flutter_module';
    const buildNumber = '1.0';

    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late CodePushClientWrapper codePushClientWrapper;
    late Platform platform;
    late Directory projectRoot;
    late ShorebirdLogger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late Progress progress;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdAndroidArtifacts shorebirdAndroidArtifacts;
    late AarReleaser aarReleaser;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
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
      operatingSystemInterface = MockOperatingSystemInterface();
      platform = MockPlatform();
      progress = MockProgress();
      projectRoot = Directory.systemTemp.createTempSync();
      logger = MockShorebirdLogger();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();
      shorebirdAndroidArtifacts = MockShorebirdAndroidArtifacts();

      when(() => argResults['build-number']).thenReturn(buildNumber);
      when(() => argResults['target-platform'])
          .thenReturn(Arch.values.map((a) => a.targetPlatformCliArg).toList());

      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
      when(() => shorebirdEnv.androidPackageName).thenReturn(packageName);

      aarReleaser = AarReleaser(
        argResults: argResults,
        flavor: null,
        target: null,
      );
    });

    group('releaseType', () {
      test('is aar', () {
        expect(aarReleaser.releaseType, ReleaseType.aar);
      });
    });

    group('requiresReleaseVersionArg', () {
      test('is true', () {
        expect(aarReleaser.requiresReleaseVersionArg, isTrue);
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
            () => runWithOverrides(aarReleaser.assertPreconditions),
            returnsNormally,
          );
        });

        group('when androidPackageName is null', () {
          setUp(() {
            when(() => shorebirdEnv.androidPackageName).thenReturn(null);
          });

          test('logs error and exits with code 64', () async {
            await expectLater(
              () => runWithOverrides(aarReleaser.assertPreconditions),
              exitsWithCode(ExitCode.config),
            );
            verify(
              () =>
                  logger.err('Could not find androidPackage in pubspec.yaml.'),
            ).called(1);
          });
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
            () => runWithOverrides(aarReleaser.assertPreconditions),
            exitsWithCode(exception.exitCode),
          );
          verify(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: true,
              checkShorebirdInitialized: true,
            ),
          ).called(1);
        });
      });
    });

    group('assertArgsAreValid', () {
      group('when release-version was not provided', () {
        setUp(() {
          when(() => argResults.wasParsed('release-version')).thenReturn(false);
        });

        test('exits with code 64', () async {
          await expectLater(
            () => runWithOverrides(aarReleaser.assertArgsAreValid),
            exitsWithCode(ExitCode.usage),
          );
        });
      });

      group('when arguments are valid', () {
        setUp(() {
          when(() => argResults.wasParsed('release-version')).thenReturn(true);
        });

        test('returns normally', () {
          expect(
            () => runWithOverrides(aarReleaser.assertArgsAreValid),
            returnsNormally,
          );
        });
      });
    });

    group('buildReleaseArtifacts', () {
      const flutterVersionAndRevision = '3.10.6 (83305b5088)';

      void setUpProjectRootArtifacts() {
        final aarDir = p.join(
          projectRoot.path,
          'build',
          'host',
          'outputs',
          'repo',
          'com',
          'example',
          'my_flutter_module',
          'flutter_release',
          buildNumber,
        );
        final aarPath = p.join(aarDir, 'flutter_release-$buildNumber.aar');
        for (final archMetadata in Arch.values) {
          final artifactPath = p.join(
            aarDir,
            'flutter_release-$buildNumber',
            'jni',
            archMetadata.androidBuildPath,
            'libapp.so',
          );
          File(artifactPath).createSync(recursive: true);
        }
        File(aarPath).createSync(recursive: true);
      }

      setUp(() {
        when(() => argResults['android-artifact']).thenReturn('apk');
        when(
          () => artifactBuilder.buildAar(
            buildNumber: any(named: 'buildNumber'),
            targetPlatforms: any(named: 'targetPlatforms'),
          ),
        ).thenAnswer(
          (_) async => File(''),
        );
        when(
          () => shorebirdFlutter.getVersionAndRevision(),
        ).thenAnswer((_) async => flutterVersionAndRevision);

        setUpProjectRootArtifacts();
      });

      group('when build succeeds', () {
        test('produces aar in release directory', () async {
          final aar = await runWithOverrides(
            () => aarReleaser.buildReleaseArtifacts(),
          );

          expect(aar.path, p.join(projectRoot.path, 'release'));
          verify(
            () => artifactBuilder.buildAar(
              buildNumber: buildNumber,
              targetPlatforms: Arch.values.toSet(),
            ),
          ).called(1);
        });
      });

      group('when build fails', () {
        setUp(() {
          when(
            () => artifactBuilder.buildAar(
              buildNumber: any(named: 'buildNumber'),
              targetPlatforms: any(named: 'targetPlatforms'),
            ),
          ).thenThrow(Exception('build failed'));
        });

        test('logs error and exits with code 70', () async {
          await expectLater(
            () => runWithOverrides(() => aarReleaser.buildReleaseArtifacts()),
            exitsWithCode(ExitCode.software),
          );
          verify(
            () => logger.err('Failed to build aar: Exception: build failed'),
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
          () => aarReleaser.getReleaseVersion(
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
          () => shorebirdAndroidArtifacts.extractAar(
            packageName: any(named: 'packageName'),
            buildNumber: any(named: 'buildNumber'),
            unzipFn: any(named: 'unzipFn'),
          ),
        ).thenAnswer((_) async => Directory('path'));
        when(
          () => codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            platform: any(named: 'platform'),
            aarPath: any(named: 'aarPath'),
            extractedAarDir: any(named: 'extractedAarDir'),
            architectures: any(named: 'architectures'),
          ),
        ).thenAnswer((_) async {});
      });

      test('uploads artifacts', () async {
        await runWithOverrides(
          () => aarReleaser.uploadReleaseArtifacts(
            release: release,
            appId: appId,
          ),
        );

        verify(
          () => codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
            appId: appId,
            releaseId: release.id,
            platform: ReleasePlatform.android,
            aarPath: any(
              named: 'aarPath',
              that: endsWith(
                p.join(
                  'build',
                  'host',
                  'outputs',
                  'repo',
                  'com',
                  'example',
                  'my_flutter_module',
                  'flutter_release',
                  '1.0',
                  'flutter_release-1.0.aar',
                ),
              ),
            ),
            extractedAarDir: 'path',
            architectures: Arch.values,
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

      test('returns expected metadata', () async {
        expect(
          await runWithOverrides(aarReleaser.releaseMetadata),
          equals(
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
          ),
        );
      });
    });

    group('postReleaseInstructions', () {
      test('returns expected instructions', () {
        expect(
          runWithOverrides(() => aarReleaser.postReleaseInstructions),
          equals('''

Your next steps:

1. Add the aar repo and Shorebird's maven url to your app's settings.gradle:

Note: The maven url needs to be a relative path from your settings.gradle file to the aar library. The code below assumes your Flutter module is in a sibling directory of your Android app.

${lightCyan.wrap('''
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
+       maven {
+           url '../${p.basename(shorebirdEnv.getShorebirdProjectRoot()!.path)}/${p.relative(p.join(projectRoot.path, 'release'))}'
+       }
+       maven {
-           url 'https://storage.googleapis.com/download.flutter.io'
+           url 'https://download.shorebird.dev/download.flutter.io'
+       }
    }
}
''')}

2. Add this module as a dependency in your app's build.gradle:
${lightCyan.wrap('''
dependencies {
  // ...
  releaseImplementation '${shorebirdEnv.androidPackageName}:flutter_release:$buildNumber'
  // ...
}''')}
'''),
        );
      });
    });
  });
}

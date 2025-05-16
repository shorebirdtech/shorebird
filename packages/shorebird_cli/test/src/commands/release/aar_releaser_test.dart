import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/release/aar_releaser.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
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
    late CodeSigner codeSigner;
    late Directory projectRoot;
    late ShorebirdLogger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late Progress progress;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdAndroidArtifacts shorebirdAndroidArtifacts;
    late AarReleaser aarReleaser;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          codeSignerRef.overrideWith(() => codeSigner),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          shorebirdAndroidArtifactsRef.overrideWith(
            () => shorebirdAndroidArtifacts,
          ),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(ReleasePlatform.android);
    });

    setUp(() {
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      codePushClientWrapper = MockCodePushClientWrapper();
      codeSigner = MockCodeSigner();
      operatingSystemInterface = MockOperatingSystemInterface();
      progress = MockProgress();
      projectRoot = Directory.systemTemp.createTempSync();
      logger = MockShorebirdLogger();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();
      shorebirdAndroidArtifacts = MockShorebirdAndroidArtifacts();

      when(() => argResults['build-number']).thenReturn(buildNumber);
      when(
        () => argResults['target-platform'],
      ).thenReturn(Arch.values.map((a) => a.targetPlatformCliArg).toList());
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(false);

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

    group('minimumFlutterVersion', () {
      test('is null', () {
        // Shorebird has always had aar support, so we don't need to
        // specify a minimum Flutter version.
        expect(aarReleaser.minimumFlutterVersion, isNull);
      });
    });

    group('artifactDisplayName', () {
      test('has expected value', () {
        expect(aarReleaser.artifactDisplayName, 'Android archive');
      });
    });

    group('assertPreconditions', () {
      group('when validation succeeds', () {
        setUp(() {
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
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
              checkShorebirdInitialized: any(
                named: 'checkShorebirdInitialized',
              ),
              validators: any(named: 'validators'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final exception = ValidationFailedException();
          when(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
              checkShorebirdInitialized: any(
                named: 'checkShorebirdInitialized',
              ),
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
        when(() => argResults['artifact']).thenReturn('apk');
        when(
          () => artifactBuilder.buildAar(
            buildNumber: any(named: 'buildNumber'),
            targetPlatforms: any(named: 'targetPlatforms'),
            args: any(named: 'args'),
          ),
        ).thenAnswer((_) async => File(''));

        setUpProjectRootArtifacts();
      });

      group('when build succeeds', () {
        group('when platform was specified via arg results rest', () {
          setUp(() {
            when(() => argResults.rest).thenReturn(['android', '--verbose']);
          });

          test('produces aar in release directory', () async {
            final aar = await runWithOverrides(
              () => aarReleaser.buildReleaseArtifacts(),
            );

            expect(aar.path, p.join(projectRoot.path, 'release'));
            verify(
              () => artifactBuilder.buildAar(
                buildNumber: buildNumber,
                targetPlatforms: Arch.values.toSet(),
                args: ['--verbose'],
              ),
            ).called(1);
          });
        });

        test('produces aar in release directory', () async {
          final aar = await runWithOverrides(
            () => aarReleaser.buildReleaseArtifacts(),
          );

          expect(aar.path, p.join(projectRoot.path, 'release'));
          verify(
            () => artifactBuilder.buildAar(
              buildNumber: buildNumber,
              targetPlatforms: Arch.values.toSet(),
              args: [],
            ),
          ).called(1);
        });

        group('when a patch signing key path is provided', () {
          const base64PublicKey = 'base64PublicKey';

          setUp(() {
            final patchSigningPublicKeyFile = File(
              p.join(
                Directory.systemTemp.createTempSync().path,
                'patch-signing-public-key.pem',
              ),
            )..createSync(recursive: true);
            when(
              () => argResults[CommonArguments.publicKeyArg.name],
            ).thenReturn(patchSigningPublicKeyFile.path);

            when(
              () => artifactBuilder.buildAar(
                buildNumber: any(named: 'buildNumber'),
                targetPlatforms: any(named: 'targetPlatforms'),
                args: any(named: 'args'),
                base64PublicKey: any(named: 'base64PublicKey'),
              ),
            ).thenAnswer((_) async => File(''));

            when(
              () => codeSigner.base64PublicKey(any()),
            ).thenReturn(base64PublicKey);
          });

          test(
            'encodes the patch signing public key and forward it to buildAar',
            () async {
              await runWithOverrides(() => aarReleaser.buildReleaseArtifacts());

              verify(
                () => artifactBuilder.buildAar(
                  buildNumber: buildNumber,
                  targetPlatforms: any(named: 'targetPlatforms'),
                  args: any(named: 'args'),
                  base64PublicKey: base64PublicKey,
                ),
              ).called(1);
            },
          );
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
          () =>
              aarReleaser.getReleaseVersion(releaseArtifactRoot: Directory('')),
        );
        expect(result, releaseVersion);
      });
    });

    group('uploadReleaseArtifacts', () {
      const releaseVersion = '1.0.0';
      const appId = 'appId';
      const flutterRevision = 'deadbeef';
      const flutterVersion = '3.22.0';

      final release = Release(
        id: 42,
        appId: appId,
        version: releaseVersion,
        flutterRevision: flutterRevision,
        flutterVersion: flutterVersion,
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

    group('updatedReleaseMetadata', () {
      test('returns expected metadata', () async {
        final metadata = UpdateReleaseMetadata.forTest();
        expect(
          aarReleaser.updatedReleaseMetadata(metadata),
          completion(metadata),
        );
      });
    });

    group('postReleaseInstructions', () {
      test('returns expected instructions', () {
        expect(
          runWithOverrides(() => aarReleaser.postReleaseInstructions),
          equals(
            '''

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
''',
          ),
        );
      });
    });
  });
}

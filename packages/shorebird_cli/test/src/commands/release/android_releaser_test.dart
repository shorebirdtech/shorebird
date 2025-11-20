import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/release/android_releaser.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
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
    late CodeSigner codeSigner;
    late Doctor doctor;
    late Directory projectRoot;
    late FlavorValidator flavorValidator;
    late ShorebirdLogger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late Progress progress;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdAndroidArtifacts shorebirdAndroidArtifacts;
    late AndroidReleaser androidReleaser;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactBuilderRef.overrideWith(() => artifactBuilder),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          codeSignerRef.overrideWith(() => codeSigner),
          doctorRef.overrideWith(() => doctor),
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
      doctor = MockDoctor();
      flavorValidator = MockFlavorValidator();
      operatingSystemInterface = MockOperatingSystemInterface();
      progress = MockProgress();
      projectRoot = Directory.systemTemp.createTempSync();
      logger = MockShorebirdLogger();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();
      shorebirdAndroidArtifacts = MockShorebirdAndroidArtifacts();

      when(
        () => argResults['target-platform'],
      ).thenReturn(Arch.values.map((a) => a.targetPlatformCliArg).toList());
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(false);

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

    group('minimumFlutterVersion', () {
      test('is null', () {
        // Shorebird has always had Android support, so we don't need to
        // specify a minimum Flutter version.
        expect(androidReleaser.minimumFlutterVersion, isNull);
      });
    });

    group('artifactDisplayName', () {
      test('has expected value', () {
        expect(androidReleaser.artifactDisplayName, 'Android app bundle');
      });
    });

    group('assertPreconditions', () {
      setUp(() {
        when(
          () => doctor.androidCommandValidators,
        ).thenReturn([flavorValidator]);
        when(flavorValidator.validate).thenAnswer((_) async => []);
      });

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
            () => runWithOverrides(androidReleaser.assertPreconditions),
            exitsWithCode(exception.exitCode),
          );
          verify(
            () => shorebirdValidator.validatePreconditions(
              checkUserIsAuthenticated: true,
              checkShorebirdInitialized: true,
              validators: [flavorValidator],
            ),
          ).called(1);
        });
      });
    });

    group('assertArgsAreValid', () {
      group('when release-version is passed', () {
        setUp(() {
          when(() => argResults.wasParsed('release-version')).thenReturn(true);
        });

        test('logs error and exits with usage err', () async {
          await expectLater(
            () => runWithOverrides(androidReleaser.assertArgsAreValid),
            exitsWithCode(ExitCode.usage),
          );

          verify(
            () => logger.err(
              '''
The "--release-version" flag is only supported for aar and ios-framework releases.
        
To change the version of this release, change your app's version in your pubspec.yaml.''',
            ),
          ).called(1);
        });
      });

      group('when split-per-abi is true', () {
        setUp(() {
          when(() => argResults['artifact']).thenReturn('apk');
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
          when(() => argResults['artifact']).thenReturn('apk');
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
      late File aabFile;

      setUp(() {
        aabFile = File('');
        when(() => argResults['artifact']).thenReturn('aab');
        when(
          () => artifactBuilder.buildAppBundle(
            flavor: any(named: 'flavor'),
            target: any(named: 'target'),
            targetPlatforms: any(named: 'targetPlatforms'),
            args: any(named: 'args'),
          ),
        ).thenAnswer((_) async => aabFile);
        when(
          () => artifactBuilder.buildApk(
            flavor: any(named: 'flavor'),
            target: any(named: 'target'),
            targetPlatforms: any(named: 'targetPlatforms'),
            args: any(named: 'args'),
          ),
        ).thenAnswer((_) async => File(''));
        when(
          () => shorebirdAndroidArtifacts.findAab(
            project: any(named: 'project'),
            flavor: any(named: 'flavor'),
          ),
        ).thenReturn(aabFile);
      });

      group('when platform was specified via arg results rest', () {
        setUp(() {
          when(() => argResults.rest).thenReturn(['android', '--verbose']);
        });

        test('returns the path to the aab', () async {
          final result = await runWithOverrides(
            () => androidReleaser.buildReleaseArtifacts(),
          );
          expect(result, aabFile);
          verify(
            () => artifactBuilder.buildAppBundle(
              targetPlatforms: Arch.values,
              args: ['--verbose'],
            ),
          ).called(1);
        });
      });

      test('returns the path to the aab', () async {
        final result = await runWithOverrides(
          () => androidReleaser.buildReleaseArtifacts(),
        );
        expect(result, aabFile);
        verify(
          () => artifactBuilder.buildAppBundle(
            targetPlatforms: Arch.values,
            args: [],
          ),
        ).called(1);
      });

      test('does not built apk by default', () async {
        await runWithOverrides(() => androidReleaser.buildReleaseArtifacts());
        verifyNever(
          () => artifactBuilder.buildApk(
            flavor: any(named: 'flavor'),
            target: any(named: 'target'),
            targetPlatforms: any(named: 'targetPlatforms'),
            args: any(named: 'args'),
          ),
        );
      });

      group('when apk is requested', () {
        setUp(() {
          when(() => argResults['artifact']).thenReturn('apk');
        });

        test('builds apk', () async {
          await runWithOverrides(() => androidReleaser.buildReleaseArtifacts());
          verify(() => logger.info('Building APK')).called(1);
          verify(
            () => artifactBuilder.buildApk(
              targetPlatforms: Arch.values,
              args: [],
            ),
          ).called(1);
        });
      });

      group('with flavor and target', () {
        const flavor = 'my-flavor';
        const target = 'my-target';

        setUp(() {
          when(() => argResults['artifact']).thenReturn('apk');
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
              args: [],
            ),
          ).called(1);
          verify(
            () => artifactBuilder.buildApk(
              flavor: flavor,
              target: target,
              targetPlatforms: Arch.values,
              args: [],
            ),
          ).called(1);
        });
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
            () => artifactBuilder.buildAppBundle(
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
              targetPlatforms: any(named: 'targetPlatforms'),
              args: any(named: 'args'),
              base64PublicKey: any(named: 'base64PublicKey'),
            ),
          ).thenAnswer((_) async => aabFile);
          when(
            () => artifactBuilder.buildApk(
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
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
          'encodes the patch signing public key and forward it to buildAab',
          () async {
            await runWithOverrides(
              () => androidReleaser.buildReleaseArtifacts(),
            );

            verify(
              () => artifactBuilder.buildAppBundle(
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
                targetPlatforms: any(named: 'targetPlatforms'),
                args: any(named: 'args'),
                base64PublicKey: base64PublicKey,
              ),
            ).called(1);
          },
        );

        group('when building apk', () {
          setUp(() {
            when(() => argResults['artifact']).thenReturn('apk');
          });

          test(
            'encodes the patch signing public key and forward it to buildApk',
            () async {
              await runWithOverrides(
                () => androidReleaser.buildReleaseArtifacts(),
              );

              verify(
                () => artifactBuilder.buildAppBundle(
                  flavor: any(named: 'flavor'),
                  target: any(named: 'target'),
                  targetPlatforms: any(named: 'targetPlatforms'),
                  args: any(named: 'args'),
                  base64PublicKey: base64PublicKey,
                ),
              ).called(1);

              verify(
                () => artifactBuilder.buildApk(
                  flavor: any(named: 'flavor'),
                  target: any(named: 'target'),
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
      const flutterVersion = '3.22.1';

      final release = Release(
        id: 42,
        appId: appId,
        version: releaseVersion,
        flutterRevision: flutterRevision,
        flutterVersion: flutterVersion,
        displayName: '1.2.3+1',
        platformStatuses: const {},
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

      test(
        'calls codePushClientWrapper.createAndroidReleaseArtifacts',
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
        },
      );
    });

    group('updatedReleaseMetadata', () {
      const flutterRevision = '853d13d954df3b6e9c2f07b72062f33c52a9a64b';
      const operatingSystem = 'macos';
      const operatingSystemVersion = '11.0.0';
      const metadata = UpdateReleaseMetadata(
        releasePlatform: ReleasePlatform.android,
        flutterVersionOverride: null,
        environment: BuildEnvironmentMetadata(
          flutterRevision: flutterRevision,
          operatingSystem: operatingSystem,
          operatingSystemVersion: operatingSystemVersion,
          shorebirdVersion: packageVersion,
          shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
          usesShorebirdCodePushPackage: true,
        ),
      );

      group('when an apk is generated', () {
        setUp(() {
          when(() => argResults['artifact']).thenReturn('apk');
        });

        test('returns expected metadata', () async {
          expect(
            runWithOverrides(
              () => androidReleaser.updatedReleaseMetadata(metadata),
            ),
            completion(
              const UpdateReleaseMetadata(
                releasePlatform: ReleasePlatform.android,
                flutterVersionOverride: null,
                generatedApks: true,
                environment: BuildEnvironmentMetadata(
                  flutterRevision: flutterRevision,
                  operatingSystem: operatingSystem,
                  operatingSystemVersion: operatingSystemVersion,
                  shorebirdVersion: packageVersion,
                  shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
                  usesShorebirdCodePushPackage: true,
                ),
              ),
            ),
          );
        });
      });

      group('when no apk is generated', () {
        setUp(() {
          when(() => argResults['artifact']).thenReturn('aab');
        });

        test('returns expected metadata', () async {
          expect(
            runWithOverrides(
              () => androidReleaser.updatedReleaseMetadata(metadata),
            ),
            completion(
              const UpdateReleaseMetadata(
                releasePlatform: ReleasePlatform.android,
                flutterVersionOverride: null,
                generatedApks: false,
                environment: BuildEnvironmentMetadata(
                  flutterRevision: flutterRevision,
                  operatingSystem: operatingSystem,
                  operatingSystemVersion: operatingSystemVersion,
                  shorebirdVersion: packageVersion,
                  shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
                  usesShorebirdCodePushPackage: true,
                ),
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
          when(() => argResults['artifact']).thenReturn('apk');
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
          when(() => argResults['artifact']).thenReturn('aab');
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

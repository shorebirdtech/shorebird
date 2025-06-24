import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/release/ios_framework_releaser.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(IosFrameworkReleaser, () {
    late ArgResults argResults;
    late ArtifactBuilder artifactBuilder;
    late ArtifactManager artifactManager;
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
          codeSignerRef.overrideWith(() => codeSigner),
          doctorRef.overrideWith(() => doctor),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          shorebirdProcessRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          xcodeBuildRef.overrideWith(() => xcodeBuild),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(ReleasePlatform.ios);
    });

    setUp(() {
      argResults = MockArgResults();
      artifactBuilder = MockArtifactBuilder();
      artifactManager = MockArtifactManager();
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
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();
      xcodeBuild = MockXcodeBuild();

      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(false);
      when(() => argResults['flutter-version']).thenReturn('latest');

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

    group('releaseType', () {
      test('is xcframework', () {
        expect(iosFrameworkReleaser.releaseType, ReleaseType.iosFramework);
      });
    });

    group('minimumFlutterVersion', () {
      test('is 3.22.2', () {
        expect(iosFrameworkReleaser.minimumFlutterVersion, Version(3, 22, 2));
      });
    });

    group('artifactDisplayName', () {
      test('has expected value', () {
        expect(iosFrameworkReleaser.artifactDisplayName, 'iOS framework');
      });
    });

    group('assertArgsAreValid', () {
      group('when split-per-abi is true', () {
        setUp(() {
          when(() => argResults.wasParsed('release-version')).thenReturn(false);
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
          when(() => argResults.wasParsed('release-version')).thenReturn(true);
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
      final flutterVersion = Version(3, 0, 0);

      setUp(() {
        when(() => doctor.iosCommandValidators).thenReturn([flavorValidator]);
        when(
          () => shorebirdFlutter.resolveFlutterVersion(any()),
        ).thenAnswer((_) async => flutterVersion);
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
              checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
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
              validators: [flavorValidator],
              supportedOperatingSystems: {Platform.macOS},
            ),
          ).called(1);
        });
      });

      group('when specified flutter version is less than minimum', () {
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
          when(() => argResults['flutter-version']).thenReturn('3.0.0');
        });
      });
    });

    group('buildReleaseArtifacts', () {
      void setUpProjectRootArtifacts() {
        // Create an xcframework in the release directory to simulate running
        // this command a subsequent time.
        Directory(
          p.join(projectRoot.path, 'release', 'Flutter.xcframework'),
        ).createSync(recursive: true);
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
          () => artifactBuilder.buildIosFramework(args: any(named: 'args')),
        ).thenAnswer(
          (_) async => AppleBuildResult(kernelFile: File('/path/to/app.dill')),
        );
        when(() => artifactManager.getAppXcframeworkDirectory()).thenReturn(
          Directory(
            p.join(projectRoot.path, 'build', 'ios', 'framework', 'Release'),
          ),
        );

        setUpProjectRootArtifacts();
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
            () => artifactBuilder.buildIosFramework(
              args: any(named: 'args'),
              base64PublicKey: any(named: 'base64PublicKey'),
            ),
          ).thenAnswer(
            (_) async =>
                AppleBuildResult(kernelFile: File('/path/to/app.dill')),
          );
          when(
            () => codeSigner.base64PublicKey(any()),
          ).thenReturn(base64PublicKey);
        });

        test(
          'encodes the patch signing public key and '
          'forward it to buildIosFramework',
          () async {
            await runWithOverrides(
              () => iosFrameworkReleaser.buildReleaseArtifacts(),
            );

            verify(
              () => artifactBuilder.buildIosFramework(
                args: any(named: 'args'),
                base64PublicKey: base64PublicKey,
              ),
            ).called(1);
          },
        );
      });

      group('when stale build/ios/shorebird directory exists', () {
        late Directory shorebirdSupplementDir;

        setUp(() {
          shorebirdSupplementDir = Directory(
            p.join(projectRoot.path, 'build', 'ios', 'shorebird'),
          )..createSync(recursive: true);
          when(
            () => artifactManager.getIosReleaseSupplementDirectory(),
          ).thenReturn(shorebirdSupplementDir);
        });

        test('deletes the directory', () async {
          expect(shorebirdSupplementDir.existsSync(), isTrue);
          await runWithOverrides(iosFrameworkReleaser.buildReleaseArtifacts);
          expect(shorebirdSupplementDir.existsSync(), isFalse);
        });
      });

      group('when platform was specified via arg results rest', () {
        setUp(() {
          when(() => argResults.rest).thenReturn(['ios', '--verbose']);
        });

        test('produces xcframework in release directory', () async {
          final xcframework = await runWithOverrides(
            iosFrameworkReleaser.buildReleaseArtifacts,
          );

          expect(xcframework.path, p.join(projectRoot.path, 'release'));
          verify(
            () => artifactBuilder.buildIosFramework(args: ['--verbose']),
          ).called(1);
        });
      });

      test('produces xcframework in release directory', () async {
        final xcframework = await runWithOverrides(
          iosFrameworkReleaser.buildReleaseArtifacts,
        );

        expect(xcframework.path, p.join(projectRoot.path, 'release'));
        verify(() => artifactBuilder.buildIosFramework(args: [])).called(1);
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

      setUp(() {
        when(
          () => codePushClientWrapper.createIosFrameworkReleaseArtifacts(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            appFrameworkPath: any(named: 'appFrameworkPath'),
            supplementPath: any(named: 'supplementPath'),
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
            supplementPath: null,
          ),
        ).called(1);
      });
    });

    group('updatedReleaseMetadata', () {
      const flutterRevision = '853d13d954df3b6e9c2f07b72062f33c52a9a64b';
      const operatingSystem = 'macos';
      const operatingSystemVersion = '11.0.0';
      const xcodeVersion = '123';
      const metadata = UpdateReleaseMetadata(
        releasePlatform: ReleasePlatform.ios,
        flutterVersionOverride: null,
        environment: BuildEnvironmentMetadata(
          flutterRevision: flutterRevision,
          operatingSystem: operatingSystem,
          operatingSystemVersion: operatingSystemVersion,
          shorebirdVersion: packageVersion,
          shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
        ),
      );

      setUp(() {
        when(() => xcodeBuild.version()).thenAnswer((_) async => xcodeVersion);
      });

      test('returns expected metadata', () async {
        expect(
          runWithOverrides(
            () => iosFrameworkReleaser.updatedReleaseMetadata(metadata),
          ),
          completion(
            const UpdateReleaseMetadata(
              releasePlatform: ReleasePlatform.ios,
              flutterVersionOverride: null,
              environment: BuildEnvironmentMetadata(
                flutterRevision: flutterRevision,
                operatingSystem: operatingSystem,
                operatingSystemVersion: operatingSystemVersion,
                shorebirdVersion: packageVersion,
                shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
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
          runWithOverrides(() => iosFrameworkReleaser.postReleaseInstructions),
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
  }, testOn: 'mac-os');
}

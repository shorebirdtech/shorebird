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

import '../../helpers.dart';
import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
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
      registerFallbackValue(File(''));
      registerFallbackValue(ReleasePlatform.ios);
    });

    setUp(() {
      argResults = MockArgResults();
      // Managed signing, the default, is covered in releaser_test.dart.
      when(() => argResults['patch-signing']).thenReturn(false);
      artifactBuilder = MockArtifactBuilder();
      artifactManager = MockArtifactManager();
      codePushClientWrapper = MockCodePushClientWrapper();
      codeSigner = MockCodeSigner();
      when(
        () => codeSigner.canonicalPublicKeyPem(any()),
      ).thenAnswer(
        (invocation) => invocation.positionalArguments.single as String,
      );
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
      when(() => argResults['codesign']).thenReturn(true);
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
      test('is 3.24.0', () {
        expect(iosFrameworkReleaser.minimumFlutterVersion, Version(3, 24, 0));
      });
    });

    group('artifactDisplayName', () {
      test('has expected value', () {
        expect(iosFrameworkReleaser.artifactDisplayName, 'iOS framework');
      });
    });

    group('supplement', () {
      test('uploads under the platform supplement names', () {
        expect(iosFrameworkReleaser.supplementPlatformSubdir, equals('ios'));
        expect(
          iosFrameworkReleaser.supplementArtifactArch,
          equals('ios_framework_supplement'),
        );
      });
    });

    group('assertArgsAreValid', () {
      for (final (description, value) in [
        ('was not provided', null),
        ('is blank', '  '),
        ('is latest', 'latest'),
      ]) {
        group('when release-version $description', () {
          setUp(() {
            when(() => argResults['release-version']).thenReturn(value);
          });

          test('exits saying which version to pass', () async {
            await expectLater(
              () => runWithOverrides(iosFrameworkReleaser.assertArgsAreValid),
              exitsWithError(
                message:
                    'Missing --release-version: pass the version of the '
                    'iOS app that embeds this module.',
                hint:
                    'Run: shorebird release ios-framework '
                    '--release-version=$releaseVersionExample',
              ),
            );
          });
        });
      }

      group('when arguments are valid', () {
        setUp(() {
          when(() => argResults['release-version']).thenReturn('1.0.0+1');
        });

        test('returns normally', () {
          expect(
            () => runWithOverrides(iosFrameworkReleaser.assertArgsAreValid),
            returnsNormally,
          );
        });
      });

      group('when --obfuscate is not passed', () {
        setUp(() {
          when(() => argResults['release-version']).thenReturn('1.0.0+1');
        });

        test('returns normally', () async {
          await expectLater(
            runWithOverrides(iosFrameworkReleaser.assertArgsAreValid),
            completes,
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
              supportedOperatingSystems: {NativePlatform.macOS},
            ),
          ).called(1);
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
            () => argResults.wasParsed(CommonArguments.publicKeyArg.name),
          ).thenReturn(true);

          when(
            () => artifactBuilder.buildIosFramework(
              args: any(named: 'args'),
              base64PublicKey: any(named: 'base64PublicKey'),
              ddMaxBytes: any(named: 'ddMaxBytes'),
            ),
          ).thenAnswer(
            (_) async =>
                AppleBuildResult(kernelFile: File('/path/to/app.dill')),
          );
          when(
            () => codeSigner.base64PublicKeyFromPem(any()),
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

      group('when --no-codesign is passed', () {
        setUp(() {
          when(() => argResults['codesign']).thenReturn(false);
        });

        test('forwards --no-codesign to flutter', () async {
          await runWithOverrides(iosFrameworkReleaser.buildReleaseArtifacts);
          verify(
            () => artifactBuilder.buildIosFramework(args: ['--no-codesign']),
          ).called(1);
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

      test(
        'replaces each .xcframework from a previous release but keeps other '
        'files in the release directory',
        () async {
          final releaseDir = p.join(projectRoot.path, 'release');
          // Not empty, so renaming Flutter.xcframework onto it would fail if
          // it were left in place.
          final staleShorebirdFlutterMarker = File(
            p.join(releaseDir, 'ShorebirdFlutter.xcframework', 'stale'),
          )..createSync(recursive: true);
          final stalePlugin = Directory(
            p.join(releaseDir, 'RemovedPlugin.xcframework'),
          )..createSync(recursive: true);
          // What `shorebird release aar` writes to the same directory.
          final aarFile = File(
            p.join(releaseDir, 'com', 'example', 'flutter_release-1.0.aar'),
          )..createSync(recursive: true);

          await runWithOverrides(iosFrameworkReleaser.buildReleaseArtifacts);

          expect(aarFile.existsSync(), isTrue);
          expect(stalePlugin.existsSync(), isFalse);
          expect(staleShorebirdFlutterMarker.existsSync(), isFalse);
          expect(
            Directory(
              p.join(releaseDir, 'ShorebirdFlutter.xcframework'),
            ).existsSync(),
            isTrue,
          );
          expect(
            Directory(p.join(releaseDir, 'Flutter.xcframework')).existsSync(),
            isFalse,
          );
        },
      );

      test('forwards the target to buildIosFramework', () async {
        when(
          () => artifactBuilder.buildIosFramework(
            target: any(named: 'target'),
            args: any(named: 'args'),
          ),
        ).thenAnswer((_) async => AppleBuildResult(kernelFile: File('')));
        iosFrameworkReleaser = IosFrameworkReleaser(
          argResults: argResults,
          flavor: null,
          target: 'lib/main_prod.dart',
        );

        await runWithOverrides(iosFrameworkReleaser.buildReleaseArtifacts);

        verify(
          () => artifactBuilder.buildIosFramework(
            target: 'lib/main_prod.dart',
            args: [],
          ),
        ).called(1);
      });

      group('when --obfuscate is passed', () {
        setUp(() {
          when(() => argResults['obfuscate']).thenReturn(true);
          when(() => argResults.wasParsed('obfuscate')).thenReturn(true);
          when(() => shorebirdEnv.flutterRevision).thenReturn('deadbeef');
          // Non-Android pipelines always pre-strip in gen_snapshot.
          when(
            () => shorebirdFlutter.shouldPreStripLibappInGenSnapshot(
              platform: any(named: 'platform'),
              flutterRevision: any(named: 'flutterRevision'),
            ),
          ).thenAnswer((_) async => true);
          // Simulate the build creating the obfuscation map.
          when(
            () => artifactBuilder.buildIosFramework(
              args: any(named: 'args'),
            ),
          ).thenAnswer((_) async {
            final mapPath = p.join(
              projectRoot.path,
              'build',
              'shorebird',
              'obfuscation_map.json',
            );
            File(mapPath)
              ..createSync(recursive: true)
              ..writeAsStringSync('{}');
            return AppleBuildResult(kernelFile: File('/path/to/app.dill'));
          });
        });

        test('injects --save-obfuscation-map into build args', () async {
          await runWithOverrides(iosFrameworkReleaser.buildReleaseArtifacts);

          final captured = verify(
            () => artifactBuilder.buildIosFramework(
              args: captureAny(named: 'args'),
            ),
          ).captured;

          final args = captured.last as List<String>;
          expect(
            args.any(
              (a) => a.startsWith(
                '--extra-gen-snapshot-options=--save-obfuscation-map=',
              ),
            ),
            isTrue,
          );
        });

        test('logs detail about map location', () async {
          await runWithOverrides(iosFrameworkReleaser.buildReleaseArtifacts);

          verify(
            () => logger.detail(
              any(that: startsWith('Obfuscation map saved to')),
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
      const flutterVersion = '3.22.1';

      final release = Release(
        id: 42,
        appId: appId,
        version: releaseVersion,
        flutterRevision: flutterRevision,
        flutterVersion: flutterVersion,
        displayName: '1.2.3+1',
        platforms: const {},
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

    group('updatedReleaseMetadata', () {
      const flutterRevision = '853d13d954df3b6e9c2f07b72062f33c52a9a64b';
      const operatingSystem = 'macos';
      const operatingSystemVersion = '11.0.0';
      const xcodeVersion = '123';
      const metadata = UpdateReleaseMetadata(
        releasePlatform: ReleasePlatform.ios,
        flutterVersionOverride: null,
        includesPublicKey: false,
        environment: BuildEnvironmentMetadata(
          flutterRevision: flutterRevision,
          operatingSystem: operatingSystem,
          operatingSystemVersion: operatingSystemVersion,
          shorebirdVersion: packageVersion,
          shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
          usesShorebirdCodePushPackage: false,
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
              includesPublicKey: false,
              environment: BuildEnvironmentMetadata(
                flutterRevision: flutterRevision,
                operatingSystem: operatingSystem,
                operatingSystemVersion: operatingSystemVersion,
                shorebirdVersion: packageVersion,
                shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
                usesShorebirdCodePushPackage: false,
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
    2. Embed the App.xcframework and ShorebirdFlutter.xcframework in your Xcode project.

Instructions for these steps can be found at https://docs.shorebird.dev/code-push/guides/add-to-app/ios/#embed-the-flutter-module-in-your-ios-app.
'''),
        );
      });
    });
  }, testOn: 'mac-os');
}

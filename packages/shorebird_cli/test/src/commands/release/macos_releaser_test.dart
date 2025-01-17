import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/release.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../matchers.dart';
import '../../mocks.dart';

void main() {
  group(
    MacosReleaser,
    () {
      late ArgResults argResults;
      late ArtifactBuilder artifactBuilder;
      late ArtifactManager artifactManager;
      late CodePushClientWrapper codePushClientWrapper;
      late Directory projectRoot;
      late Doctor doctor;
      late FlavorValidator flavorValidator;
      late Progress progress;
      late ShorebirdLogger logger;
      late ShorebirdEnv shorebirdEnv;
      late ShorebirdFlutter shorebirdFlutter;
      late ShorebirdValidator shorebirdValidator;
      late XcodeBuild xcodeBuild;

      late MacosReleaser releaser;

      R runWithOverrides<R>(R Function() body) {
        return runScoped(
          body,
          values: {
            artifactBuilderRef.overrideWith(() => artifactBuilder),
            artifactManagerRef.overrideWith(() => artifactManager),
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
            doctorRef.overrideWith(() => doctor),
            loggerRef.overrideWith(() => logger),
            shorebirdEnvRef.overrideWith(() => shorebirdEnv),
            shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
            shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            xcodeBuildRef.overrideWith(() => xcodeBuild),
          },
        );
      }

      setUp(() {
        argResults = MockArgResults();
        artifactBuilder = MockArtifactBuilder();
        artifactManager = MockArtifactManager();
        codePushClientWrapper = MockCodePushClientWrapper();
        doctor = MockDoctor();
        flavorValidator = MockFlavorValidator();
        projectRoot = Directory.systemTemp.createTempSync();
        progress = MockProgress();
        logger = MockShorebirdLogger();
        shorebirdEnv = MockShorebirdEnv();
        shorebirdFlutter = MockShorebirdFlutter();
        shorebirdValidator = MockShorebirdValidator();
        xcodeBuild = MockXcodeBuild();

        when(() => argResults.rest).thenReturn([]);
        when(() => argResults.wasParsed(any())).thenReturn(false);

        when(() => logger.progress(any())).thenReturn(progress);

        releaser = MacosReleaser(
          argResults: argResults,
          flavor: null,
          target: null,
        );
      });

      group('releaseType', () {
        test('is macos', () {
          expect(releaser.releaseType, ReleaseType.macos);
        });
      });

      group('assertPreconditions', () {
        final flutterVersion = Version(3, 0, 0);

        setUp(() {
          when(() => doctor.macosCommandValidators)
              .thenReturn([flavorValidator]);
          when(() => shorebirdFlutter.resolveFlutterVersion(any()))
              .thenAnswer((_) async => flutterVersion);
          when(flavorValidator.validate).thenAnswer((_) async => []);
        });

        group('when validation succeeds', () {
          setUp(() {
            when(
              () => shorebirdValidator.validatePreconditions(
                checkUserIsAuthenticated:
                    any(named: 'checkUserIsAuthenticated'),
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
              () => runWithOverrides(releaser.assertPreconditions),
              returnsNormally,
            );
          });
        });

        group('when validation fails', () {
          final exception = ValidationFailedException();

          setUp(() {
            when(
              () => shorebirdValidator.validatePreconditions(
                checkUserIsAuthenticated:
                    any(named: 'checkUserIsAuthenticated'),
                checkShorebirdInitialized:
                    any(named: 'checkShorebirdInitialized'),
                validators: any(named: 'validators'),
                supportedOperatingSystems:
                    any(named: 'supportedOperatingSystems'),
              ),
            ).thenThrow(exception);
          });

          test('exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(releaser.assertPreconditions),
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
                checkUserIsAuthenticated:
                    any(named: 'checkUserIsAuthenticated'),
                checkShorebirdInitialized:
                    any(named: 'checkShorebirdInitialized'),
                validators: any(named: 'validators'),
                supportedOperatingSystems:
                    any(named: 'supportedOperatingSystems'),
              ),
            ).thenAnswer((_) async {});
            when(() => argResults['flutter-version']).thenReturn('3.0.0');
          });

          test('logs error and exits with code 64', () async {
            await expectLater(
              () => runWithOverrides(releaser.assertPreconditions),
              exitsWithCode(ExitCode.usage),
            );

            verify(
              () => logger.err(
                '''
macOS releases are not supported with Flutter versions older than $minimumSupportedMacosFlutterVersion.
For more information see: ${supportedFlutterVersionsUrl.toLink()}''',
              ),
            ).called(1);
          });
        });
      });

      group('assertArgsAreValid', () {
        group('when release-version is passed', () {
          setUp(() {
            when(() => argResults.wasParsed('release-version'))
                .thenReturn(true);
          });

          test('logs error and exits with usage err', () async {
            await expectLater(
              () => runWithOverrides(releaser.assertArgsAreValid),
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

        group('when --obfuscate is passed', () {
          setUp(() {
            when(() => argResults.rest).thenReturn(['--obfuscate']);
          });

          test('logs error and exits', () async {
            await expectLater(
              runWithOverrides(releaser.assertArgsAreValid),
              exitsWithCode(ExitCode.unavailable),
            );

            verify(
              () => logger.err(
                'Shorebird does not currently support obfuscation on macOS.',
              ),
            ).called(1);
            verify(
              () => logger.info(
                '''We hope to support obfuscation in the future. We are tracking this work at ${link(uri: Uri.parse('https://github.com/shorebirdtech/shorebird/issues/1619'))}.''',
              ),
            ).called(1);
          });
        });

        group('when --obfuscate is not passed', () {
          test('returns normally', () async {
            await expectLater(
              runWithOverrides(releaser.assertArgsAreValid),
              completes,
            );
          });
        });
      });

      group('buildReleaseArtifacts', () {
        const flutterVersionAndRevision = '3.10.6 (83305b5088)';

        late Directory appDirectory;

        setUp(() {
          when(() => argResults['codesign']).thenReturn(true);

          when(
            () => artifactBuilder.buildMacos(
              codesign: any(named: 'codesign'),
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
              args: any(named: 'args'),
              buildProgress: any(named: 'buildProgress'),
            ),
          ).thenAnswer(
            (_) async => MacosBuildResult(
              kernelFile: File('/path/to/app.dill'),
            ),
          );

          appDirectory = Directory.systemTemp.createTempSync();
          when(
            () => artifactManager.getMacOSAppDirectory(),
          ).thenReturn(appDirectory);

          when(
            () => shorebirdEnv.getShorebirdProjectRoot(),
          ).thenReturn(projectRoot);
          when(
            () => shorebirdFlutter.getVersionAndRevision(),
          ).thenAnswer((_) async => flutterVersionAndRevision);
        });

        group('when flavor is provided', () {
          const flavor = 'myFlavor';

          setUp(() {
            releaser = MacosReleaser(
              argResults: argResults,
              flavor: flavor,
              target: null,
            );

            when(
              () => artifactManager.getMacOSAppDirectory(flavor: flavor),
            ).thenReturn(appDirectory);
          });

          test('forwards flavor to artifact builder', () async {
            await runWithOverrides(releaser.buildReleaseArtifacts);

            verify(
              () => artifactBuilder.buildMacos(
                flavor: flavor,
                args: any(named: 'args'),
                buildProgress: any(named: 'buildProgress'),
              ),
            ).called(1);
            verify(
              () => artifactManager.getMacOSAppDirectory(flavor: flavor),
            ).called(1);
          });
        });

        group('when not codesigning', () {
          setUp(() {
            when(() => argResults['codesign']).thenReturn(false);
          });

          test('logs warning about patching', () async {
            await runWithOverrides(releaser.buildReleaseArtifacts);

            verify(
              () => logger.info(
                '''Building for device with codesigning disabled. You will have to manually codesign before deploying to device.''',
              ),
            ).called(1);
            verify(
              () => logger.warn(
                '''shorebird preview will not work for releases created with "--no-codesign". However, you can still preview your app by signing the generated .xcarchive in Xcode.''',
              ),
            ).called(1);
          });
        });

        group('when build fails', () {
          setUp(() {
            when(
              () => artifactBuilder.buildMacos(
                codesign: any(named: 'codesign'),
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
                args: any(named: 'args'),
                buildProgress: any(named: 'buildProgress'),
              ),
            ).thenThrow(ArtifactBuildException('Failed to build'));
          });

          test('logs error and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(releaser.buildReleaseArtifacts),
              exitsWithCode(ExitCode.software),
            );

            verify(
              () => progress.fail('Failed to build'),
            ).called(1);
          });
        });

        group('when build succeeds', () {
          group('when platform was specified via arg results rest', () {
            setUp(() {
              when(() => argResults.rest).thenReturn(['macos', '--verbose']);
            });

            test('verifies artifacts exist and returns xcarchive path',
                () async {
              expect(
                await runWithOverrides(releaser.buildReleaseArtifacts),
                equals(appDirectory),
              );

              verify(() => artifactManager.getMacOSAppDirectory()).called(1);
              verify(
                () => artifactBuilder.buildMacos(
                  args: ['--verbose'],
                  buildProgress: any(named: 'buildProgress'),
                ),
              ).called(1);
            });
          });

          test('verifies artifacts exist and returns app path', () async {
            expect(
              await runWithOverrides(releaser.buildReleaseArtifacts),
              equals(appDirectory),
            );

            verify(() => artifactManager.getMacOSAppDirectory()).called(1);
          });
        });

        group('when app not found after build', () {
          setUp(() {
            when(() => artifactManager.getMacOSAppDirectory()).thenReturn(null);
          });

          test('logs message and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(releaser.buildReleaseArtifacts),
              exitsWithCode(ExitCode.software),
            );

            verify(
              () => logger.err('Unable to find .app directory'),
            ).called(1);
          });
        });

        group('when app not found after build', () {
          setUp(() {
            when(
              () => artifactManager.getMacOSAppDirectory(),
            ).thenReturn(null);
          });

          test('logs message and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(releaser.buildReleaseArtifacts),
              exitsWithCode(ExitCode.software),
            );

            verify(
              () => logger.err('Unable to find .app directory'),
            ).called(1);
          });
        });
      });

      group('getReleaseVersion', () {
        late Directory appDirectory;

        setUp(() {
          appDirectory = Directory.systemTemp.createTempSync();
          // The Info.plist file is expected to be in the app directory at
          // Contents/Info.plist
          Directory(p.join(appDirectory.path, 'Contents'))
              .createSync(recursive: true);
        });

        group('when plist does not exist', () {
          test('logs error and exits', () async {
            await expectLater(
              () => runWithOverrides(
                () => releaser.getReleaseVersion(
                  releaseArtifactRoot: appDirectory,
                ),
              ),
              exitsWithCode(ExitCode.software),
            );

            verify(
              () => logger.err(
                '''No Info.plist file found at ${p.join(appDirectory.path, 'Contents', 'Info.plist')}''',
              ),
            ).called(1);
          });
        });

        group('when plist does not contain version number', () {
          late File plist;
          setUp(() {
            plist = File(p.join(appDirectory.path, 'Contents', 'Info.plist'))
              ..createSync()
              ..writeAsStringSync(
                '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ApplicationProperties</key>
	<dict>
	</dict>
</dict>
</plist>'
''',
              );
          });

          test('logs error and exits', () async {
            await expectLater(
              () => runWithOverrides(
                () => releaser.getReleaseVersion(
                  releaseArtifactRoot: appDirectory,
                ),
              ),
              exitsWithCode(ExitCode.software),
            );

            verify(
              () => logger.err(
                any(
                  that: startsWith(
                    'Failed to determine release version from ${plist.path}',
                  ),
                ),
              ),
            ).called(1);
          });
        });

        group('when plist contains version number', () {
          setUp(() {
            File(p.join(appDirectory.path, 'Contents', 'Info.plist'))
              ..createSync()
              ..writeAsStringSync(
                '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ApplicationProperties</key>
	<dict>
		<key>ApplicationPath</key>
		<string>Applications/Runner.app</string>
		<key>Architectures</key>
		<array>
			<string>arm64</string>
		</array>
		<key>CFBundleIdentifier</key>
		<string>com.shorebird.timeShift</string>
		<key>CFBundleShortVersionString</key>
		<string>1.2.3</string>
		<key>CFBundleVersion</key>
		<string>1</string>
	</dict>
	<key>ArchiveVersion</key>
	<integer>2</integer>
	<key>Name</key>
	<string>Runner</string>
	<key>SchemeName</key>
	<string>Runner</string>
</dict>
</plist>''',
              );
          });

          test('returns version number from plist', () async {
            expect(
              await runWithOverrides(
                () => releaser.getReleaseVersion(
                  releaseArtifactRoot: appDirectory,
                ),
              ),
              equals('1.2.3+1'),
            );
          });
        });
      });

      group('uploadReleaseArtifacts', () {
        const appId = 'appId';
        const releaseVersion = '1.0.0';
        const flutterRevision = 'deadbeef';
        const flutterVersion = '3.22.0';
        const codesign = true;
        const podfileLockContent = 'podfile-lock';

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

        late Directory appDirectory;
        late Directory supplementDirectory;
        late File podfileLockFile;

        setUp(() {
          when(() => argResults['codesign']).thenReturn(codesign);

          appDirectory = Directory.systemTemp.createTempSync();
          supplementDirectory = Directory.systemTemp.createTempSync();

          podfileLockFile = File(
            p.join(
              Directory.systemTemp.createTempSync().path,
              'Podfile.lock',
            ),
          )
            ..createSync(recursive: true)
            ..writeAsStringSync(podfileLockContent);

          when(
            () => artifactManager.getMacOSAppDirectory(),
          ).thenReturn(appDirectory);
          when(
            () => artifactManager.getMacosReleaseSupplementDirectory(),
          ).thenReturn(supplementDirectory);
          when(
            () => codePushClientWrapper.createMacosReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              appPath: any(named: 'appPath'),
              isCodesigned: any(named: 'isCodesigned'),
              podfileLockHash: any(named: 'podfileLockHash'),
              supplementPath: any(named: 'supplementPath'),
            ),
          ).thenAnswer((_) async => {});

          when(
            () => shorebirdEnv.macosPodfileLockFile,
          ).thenReturn(podfileLockFile);
        });

        group('when app directory does not exist', () {
          setUp(() {
            when(() => artifactManager.getMacOSAppDirectory()).thenReturn(null);
          });

          test('logs error and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(
                () => releaser.uploadReleaseArtifacts(
                  release: release,
                  appId: appId,
                ),
              ),
              exitsWithCode(ExitCode.software),
            );

            verify(
              () => logger.err('Unable to find .app directory'),
            ).called(1);
          });
        });

        group('when supplement directory does not exist', () {
          setUp(() {
            when(
              () => artifactManager.getMacosReleaseSupplementDirectory(),
            ).thenReturn(null);
          });

          test('logs error and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(
                () => releaser.uploadReleaseArtifacts(
                  release: release,
                  appId: appId,
                ),
              ),
              exitsWithCode(ExitCode.software),
            );
            verify(
              () => logger.err('Unable to find supplement directory'),
            ).called(1);
          });
        });

        test('forwards call to codePushClientWrapper', () async {
          await runWithOverrides(
            () => releaser.uploadReleaseArtifacts(
              release: release,
              appId: appId,
            ),
          );

          verify(
            () => codePushClientWrapper.createMacosReleaseArtifacts(
              appId: appId,
              releaseId: release.id,
              appPath: appDirectory.path,
              isCodesigned: codesign,
              podfileLockHash:
                  '${sha256.convert(utf8.encode(podfileLockContent))}',
              supplementPath: supplementDirectory.path,
            ),
          ).called(1);
        });
      });

      group('updatedReleaseMetadata', () {
        const flutterRevision = '853d13d954df3b6e9c2f07b72062f33c52a9a64b';
        const operatingSystem = 'macOS';
        const operatingSystemVersion = '11.0.0';
        const xcodeVersion = '123';
        const flutterVersionOverride = '1.2.3';
        const metadata = UpdateReleaseMetadata(
          releasePlatform: ReleasePlatform.macos,
          flutterVersionOverride: flutterVersionOverride,
          environment: BuildEnvironmentMetadata(
            flutterRevision: flutterRevision,
            operatingSystem: operatingSystem,
            operatingSystemVersion: operatingSystemVersion,
            shorebirdVersion: packageVersion,
            shorebirdYaml: ShorebirdYaml(appId: 'app-id'),
          ),
        );

        setUp(() {
          when(
            () => xcodeBuild.version(),
          ).thenAnswer((_) async => xcodeVersion);
        });

        test('returns expected metadata', () async {
          expect(
            runWithOverrides(
              () => releaser.updatedReleaseMetadata(metadata),
            ),
            completion(
              const UpdateReleaseMetadata(
                releasePlatform: ReleasePlatform.macos,
                flutterVersionOverride: flutterVersionOverride,
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
        late Directory appDirectory;

        setUp(() {
          appDirectory = Directory.systemTemp.createTempSync();
          when(() => artifactManager.getMacOSAppDirectory())
              .thenReturn(appDirectory);
        });

        test('prints xcarchive upload steps', () {
          expect(
            runWithOverrides(() => releaser.postReleaseInstructions),
            equals('''

macOS app created at ${appDirectory.path}.
'''),
          );
        });
      });
    },
    testOn: 'mac-os',
  );
}

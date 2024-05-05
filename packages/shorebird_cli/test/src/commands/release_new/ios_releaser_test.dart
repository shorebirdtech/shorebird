import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release_new/ios_releaser.dart';
import 'package:shorebird_cli/src/commands/release_new/release_type.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/ios.dart';
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
    IosReleaser,
    () {
      late ArgResults argResults;
      late ArtifactBuilder artifactBuilder;
      late ArtifactManager artifactManager;
      late CodePushClientWrapper codePushClientWrapper;
      late Directory shorebirdRoot;
      late Directory projectRoot;
      late Doctor doctor;
      late Platform platform;
      late Progress progress;
      late Logger logger;
      late Ios ios;
      late OperatingSystemInterface operatingSystemInterface;
      late ShorebirdProcessResult flutterBuildProcessResult;
      late ShorebirdProcessResult flutterPubGetProcessResult;
      late ShorebirdFlutterValidator flutterValidator;
      late ShorebirdProcess shorebirdProcess;
      late ShorebirdEnv shorebirdEnv;
      late ShorebirdFlutter shorebirdFlutter;
      late ShorebirdValidator shorebirdValidator;
      late XcodeBuild xcodeBuild;
      late IosReleaser iosReleaser;

      R runWithOverrides<R>(R Function() body) {
        return runScoped(
          body,
          values: {
            artifactBuilderRef.overrideWith(() => artifactBuilder),
            artifactManagerRef.overrideWith(() => artifactManager),
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
            doctorRef.overrideWith(() => doctor),
            iosRef.overrideWith(() => ios),
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
        platform = MockPlatform();
        shorebirdRoot = Directory.systemTemp.createTempSync();
        projectRoot = Directory.systemTemp.createTempSync();
        operatingSystemInterface = MockOperatingSystemInterface();
        progress = MockProgress();
        logger = MockLogger();
        ios = MockIos();
        flutterBuildProcessResult = MockProcessResult();
        flutterPubGetProcessResult = MockProcessResult();
        flutterValidator = MockShorebirdFlutterValidator();
        shorebirdProcess = MockShorebirdProcess();
        shorebirdEnv = MockShorebirdEnv();
        shorebirdFlutter = MockShorebirdFlutter();
        shorebirdValidator = MockShorebirdValidator();
        xcodeBuild = MockXcodeBuild();

        when(() => argResults.rest).thenReturn([]);

        when(() => logger.progress(any())).thenReturn(progress);

        iosReleaser = IosReleaser(
          argResults: argResults,
          flavor: null,
          target: null,
        );
      });

      group('releaseType', () {
        test('is ios', () {
          expect(iosReleaser.releaseType, ReleaseType.ios);
        });
      });

      group('assertPreconditions', () {
        setUp(() {
          when(() => doctor.iosCommandValidators)
              .thenReturn([flutterValidator]);
          when(flutterValidator.validate).thenAnswer((_) async => []);
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
              () => runWithOverrides(iosReleaser.assertPreconditions),
              returnsNormally,
            );
          });
        });

        group('when validation fails', () {
          setUp(() {
            final exception = ValidationFailedException();
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
            final exception = ValidationFailedException();
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
            await expectLater(
              () => runWithOverrides(iosReleaser.assertPreconditions),
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

      group('assertArgsAreValid', () {
        group('when --obfuscate is passed', () {
          setUp(() {
            when(() => argResults.rest).thenReturn(['--obfuscate']);
          });

          test('logs error and exits', () async {
            await expectLater(
              runWithOverrides(iosReleaser.assertArgsAreValid),
              exitsWithCode(ExitCode.unavailable),
            );

            verify(
              () => logger.err(
                'Shorebird does not currently support obfuscation on iOS.',
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
              runWithOverrides(iosReleaser.assertArgsAreValid),
              completes,
            );
          });
        });
      });

      group('buildReleaseArtifacts', () {
        late Directory xcarchiveDirectory;
        late Directory iosAppDirectory;

        setUp(() {
          xcarchiveDirectory = Directory.systemTemp.createTempSync();
          iosAppDirectory = Directory.systemTemp.createTempSync();
          when(() => argResults['codesign']).thenReturn(true);
          when(
            () => artifactBuilder.buildIpa(
              codesign: any(named: 'codesign'),
              exportOptionsPlist: any(named: 'exportOptionsPlist'),
              flavor: any(named: 'flavor'),
              target: any(named: 'target'),
            ),
          ).thenAnswer((_) async => {});

          when(
            () => artifactManager.getIosAppDirectory(
              xcarchiveDirectory: any(named: 'xcarchiveDirectory'),
            ),
          ).thenReturn(iosAppDirectory);
          when(() => artifactManager.getXcarchiveDirectory())
              .thenReturn(xcarchiveDirectory);
          when(
            () => ios.exportOptionsPlistFromArgs(argResults),
          ).thenReturn(File(''));
          when(() => shorebirdEnv.getShorebirdProjectRoot())
              .thenReturn(projectRoot);
        });

        group('when not codesigning', () {
          setUp(() {
            when(() => argResults['codesign']).thenReturn(false);
          });

          test('logs warning about patching', () async {
            await runWithOverrides(iosReleaser.buildReleaseArtifacts);

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

        group('when export options plist fails to generate', () {
          const error = 'error';
          setUp(() {
            when(
              () => ios.exportOptionsPlistFromArgs(argResults),
            ).thenThrow(error);
          });

          test('logs error and exits with code 64', () async {
            await expectLater(
              () => runWithOverrides(iosReleaser.buildReleaseArtifacts),
              exitsWithCode(ExitCode.usage),
            );

            verify(
              () => logger.err(error),
            ).called(1);
          });
        });

        group('when build fails', () {
          setUp(() {
            when(
              () => artifactBuilder.buildIpa(
                codesign: any(named: 'codesign'),
                exportOptionsPlist: any(named: 'exportOptionsPlist'),
                flavor: any(named: 'flavor'),
                target: any(named: 'target'),
              ),
            ).thenThrow(ArtifactBuildException('Failed to build'));
          });

          test('logs error and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(iosReleaser.buildReleaseArtifacts),
              exitsWithCode(ExitCode.software),
            );

            verify(
              () => progress.fail('Failed to build'),
            ).called(1);
          });
        });

        group('when build succeeds', () {
          test('verifies artifacts exist and returns xcarchive path', () async {
            expect(
              await runWithOverrides(iosReleaser.buildReleaseArtifacts),
              equals(xcarchiveDirectory),
            );

            verify(() => artifactManager.getXcarchiveDirectory()).called(1);
            verify(
              () => artifactManager.getIosAppDirectory(
                xcarchiveDirectory: xcarchiveDirectory,
              ),
            ).called(1);
          });
        });

        group('when xcarchive not found after build', () {
          setUp(() {
            when(() => artifactManager.getXcarchiveDirectory())
                .thenReturn(null);
          });

          test('logs message and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(iosReleaser.buildReleaseArtifacts),
              exitsWithCode(ExitCode.software),
            );

            verify(
              () => logger.err('Unable to find .xcarchive directory'),
            ).called(1);
          });
        });

        group('when app not found after build', () {
          setUp(() {
            when(
              () => artifactManager.getIosAppDirectory(
                xcarchiveDirectory: any(named: 'xcarchiveDirectory'),
              ),
            ).thenReturn(null);
          });

          test('logs message and exits with code 70', () async {
            await expectLater(
              () => runWithOverrides(iosReleaser.buildReleaseArtifacts),
              exitsWithCode(ExitCode.software),
            );

            verify(
              () => logger.err('Unable to find .app directory'),
            ).called(1);
          });
        });
      });

      group('getReleaseVersion', () {
        late Directory xcarchiveDirectory;

        setUp(() {
          xcarchiveDirectory = Directory.systemTemp.createTempSync();
        });

        group('when plist does not exist', () {
          test('logs error and exits', () async {
            await expectLater(
              () => runWithOverrides(
                () => iosReleaser.getReleaseVersion(
                  releaseArtifactRoot: xcarchiveDirectory,
                ),
              ),
              exitsWithCode(ExitCode.software),
            );

            verify(
              () => logger.err(
                '''No Info.plist file found at ${p.join(xcarchiveDirectory.path, 'Info.plist')}''',
              ),
            ).called(1);
          });
        });

        group('when plist does not contain version number', () {
          late File plist;
          setUp(() {
            plist = File(p.join(xcarchiveDirectory.path, 'Info.plist'))
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
                () => iosReleaser.getReleaseVersion(
                  releaseArtifactRoot: xcarchiveDirectory,
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
            File(p.join(xcarchiveDirectory.path, 'Info.plist'))
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
                () => iosReleaser.getReleaseVersion(
                  releaseArtifactRoot: xcarchiveDirectory,
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
        const codesign = true;

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

        late Directory xcarchiveDirectory;
        late Directory iosAppDirectory;

        setUp(() {
          when(() => argResults['codesign']).thenReturn(codesign);

          xcarchiveDirectory = Directory.systemTemp.createTempSync();
          iosAppDirectory = Directory.systemTemp.createTempSync();
          when(artifactManager.getXcarchiveDirectory)
              .thenReturn(xcarchiveDirectory);
          when(
            () => artifactManager.getIosAppDirectory(
              xcarchiveDirectory: any(named: 'xcarchiveDirectory'),
            ),
          ).thenReturn(iosAppDirectory);
          when(
            () => codePushClientWrapper.createIosReleaseArtifacts(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              xcarchivePath: any(named: 'xcarchivePath'),
              runnerPath: any(named: 'runnerPath'),
              isCodesigned: any(named: 'isCodesigned'),
            ),
          ).thenAnswer((_) async => {});
        });

        test('forwards call to codePushClientWrapper', () async {
          await runWithOverrides(
            () => iosReleaser.uploadReleaseArtifacts(
              release: release,
              appId: appId,
            ),
          );

          verify(
            () => codePushClientWrapper.createIosReleaseArtifacts(
              appId: appId,
              releaseId: release.id,
              xcarchivePath: xcarchiveDirectory.path,
              runnerPath: iosAppDirectory.path,
              isCodesigned: codesign,
            ),
          ).called(1);
        });
      });

      group('releaseMetadata', () {
        const operatingSystem = 'macOS';
        const operatingSystemVersion = '11.0.0';
        const xcodeVersion = '123';
        const flutterVersionOverride = '1.2.3';

        setUp(() {
          when(() => platform.operatingSystem).thenReturn(operatingSystem);
          when(() => platform.operatingSystemVersion)
              .thenReturn(operatingSystemVersion);
          when(() => xcodeBuild.version())
              .thenAnswer((_) async => xcodeVersion);
          when(() => argResults['flutter-version'])
              .thenReturn(flutterVersionOverride);
        });

        test('returns expected metadata', () async {
          expect(
            await runWithOverrides(iosReleaser.releaseMetadata),
            const UpdateReleaseMetadata(
              releasePlatform: ReleasePlatform.ios,
              flutterVersionOverride: flutterVersionOverride,
              generatedApks: false,
              environment: BuildEnvironmentMetadata(
                operatingSystem: operatingSystem,
                operatingSystemVersion: operatingSystemVersion,
                shorebirdVersion: packageVersion,
                xcodeVersion: xcodeVersion,
              ),
            ),
          );
        });
      });

      group('postReleaseInstructions', () {
        late Directory xcarchiveDirectory;

        setUp(() {
          xcarchiveDirectory = Directory.systemTemp.createTempSync();
          when(() => artifactManager.getXcarchiveDirectory())
              .thenReturn(xcarchiveDirectory);
        });

        group('when codesigning', () {
          setUp(() {
            when(() => argResults['codesign']).thenReturn(true);
          });

          group('when no ipa found', () {
            test('logs error and exits', () async {
              await expectLater(
                () => runWithOverrides(
                  () => iosReleaser.postReleaseInstructions,
                ),
                exitsWithCode(ExitCode.software),
              );

              verify(
                () => logger.err('Could not find ipa file'),
              ).called(1);
            });
          });

          group('when ipa found', () {
            late File ipa;
            setUp(() {
              final tempDir = Directory.systemTemp.createTempSync();
              ipa = File(p.join(tempDir.path, 'ipa.ipa'))..createSync();
              when(() => artifactManager.getIpa()).thenReturn(ipa);
            });

            test('prints ipa upload steps', () {
              expect(
                runWithOverrides(() => iosReleaser.postReleaseInstructions),
                equals('''

Your next step is to upload your app to App Store Connect.

To upload to the App Store, do one of the following:
    1. Open ${lightCyan.wrap(p.relative(xcarchiveDirectory.path))} in Xcode and use the "Distribute App" flow.
    2. Drag and drop the ${lightCyan.wrap(p.relative(ipa.path))} bundle into the Apple Transporter macOS app (https://apps.apple.com/us/app/transporter/id1450874784).
    3. Run ${lightCyan.wrap('xcrun altool --upload-app --type ios -f ${p.relative(ipa.path)} --apiKey your_api_key --apiIssuer your_issuer_id')}.
       See "man altool" for details about how to authenticate with the App Store Connect API key.
'''),
              );
            });
          });
        });

        group('when not codesigning', () {
          setUp(() {
            when(() => argResults['codesign']).thenReturn(false);
          });

          test('prints xcarchive upload steps', () {
            expect(
              runWithOverrides(() => iosReleaser.postReleaseInstructions),
              equals(
                '''

Your next step is to submit the archive at ${lightCyan.wrap(p.relative(xcarchiveDirectory.path))} to the App Store using Xcode.

You can open the archive in Xcode by running:
    ${lightCyan.wrap('open ${p.relative(xcarchiveDirectory.path)}')}

${styleBold.wrap('Make sure to uncheck "Manage Version and Build Number", or else shorebird will not work.')}
''',
              ),
            );
          });
        });
      });
    },
    testOn: 'mac-os',
  );
}

import 'dart:io' hide Platform;

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../mocks.dart';

void main() {
  group(ReleaseIosCommand, () {
    const appId = 'test-app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const flutterVersionAndRevision = '3.10.6 (83305b5088)';
    const versionName = '1.2.3';
    const versionCode = '1';
    const version = '$versionName+$versionCode';
    const operatingSystem = 'macOS';
    const operatingSystemVersion = '11.0.0';
    const xcodeVersion = '12.0';
    const appDisplayName = 'Test App';
    const arch = 'armv7';
    const releasePlatform = ReleasePlatform.ios;
    const ipaPath = 'build/ios/ipa/Runner.ipa';
    final appMetadata = AppMetadata(
      appId: appId,
      displayName: appDisplayName,
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );
    final release = Release(
      id: 0,
      appId: appId,
      version: version,
      flutterRevision: flutterRevision,
      displayName: '1.2.3+1',
      platformStatuses: {},
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );
    const infoPlistContent = '''
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
</plist>''';
    const emptyPlistContent = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ApplicationProperties</key>
	<dict>
	</dict>
</dict>
</plist>'
''';
    const pubspecYamlContent = '''
name: example
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  assets:
    - shorebird.yaml''';

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory shorebirdRoot;
    late Directory projectRoot;
    late Doctor doctor;
    late Platform platform;
    late Auth auth;
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
    late ReleaseIosCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
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

    void setUpProjectRoot() {
      File(
        p.join(projectRoot.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      File(
        p.join(projectRoot.path, 'shorebird.yaml'),
      ).writeAsStringSync('app_id: $appId');
      File(
        p.join(
          projectRoot.path,
          'build',
          'ios',
          'archive',
          'Runner.xcarchive',
          'Info.plist',
        ),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync(infoPlistContent);
      Directory(
        p.join(
          projectRoot.path,
          'build',
          'ios',
          'archive',
          'Runner.xcarchive',
          'Products',
          'Applications',
          'Runner.app',
        ),
      ).createSync(recursive: true);
      File(p.join(projectRoot.path, ipaPath)).createSync(recursive: true);
    }

    setUpAll(() {
      registerFallbackValue(File(''));
      registerFallbackValue(ReleasePlatform.ios);
      registerFallbackValue(ReleaseStatus.draft);
      registerFallbackValue(FakeRelease());
      registerFallbackValue(FakeShorebirdProcess());
    });

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      doctor = MockDoctor();
      platform = MockPlatform();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      projectRoot = Directory.systemTemp.createTempSync();
      auth = MockAuth();
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

      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
      when(
        () => shorebirdEnv.copyWith(
          flutterRevisionOverride: any(named: 'flutterRevisionOverride'),
        ),
      ).thenAnswer((invocation) {
        when(() => shorebirdEnv.flutterRevision).thenReturn(
          invocation.namedArguments[#flutterRevisionOverride] as String,
        );
        return shorebirdEnv;
      });
      when(
        () => shorebirdFlutter.getVersionAndRevision(),
      ).thenAnswer((_) async => flutterVersionAndRevision);
      when(
        () => shorebirdFlutter.installRevision(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => shorebirdProcess.run(
          'flutter',
          ['--no-version-check', 'pub', 'get', '--offline'],
          runInShell: any(named: 'runInShell'),
          useVendedFlutter: false,
        ),
      ).thenAnswer((_) async => flutterPubGetProcessResult);
      when(
        () => shorebirdProcess.run(
          'flutter',
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => flutterBuildProcessResult);
      when(() => argResults['arch']).thenReturn(arch);
      when(() => argResults['codesign']).thenReturn(true);
      when(() => argResults['platform']).thenReturn(releasePlatform);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(true);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.confirm(any())).thenReturn(true);
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(version);
      when(() => ios.exportOptionsPlistFromArgs(argResults)).thenReturn(
        File('.'),
      );
      when(
        () => operatingSystemInterface.which('flutter'),
      ).thenReturn('/path/to/flutter');
      when(() => platform.operatingSystem).thenReturn(operatingSystem);
      when(() => platform.operatingSystemVersion)
          .thenReturn(operatingSystemVersion);
      when(
        () => flutterBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => flutterPubGetProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
      ).thenAnswer((_) async => appMetadata);
      when(
        () => codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => codePushClientWrapper.ensureReleaseIsNotActive(
          release: any(named: 'release'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => codePushClientWrapper.createRelease(
          appId: any(named: 'appId'),
          version: any(named: 'version'),
          flutterRevision: any(named: 'flutterRevision'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async => release);
      when(
        () => codePushClientWrapper.createIosReleaseArtifacts(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          xcarchivePath: any(named: 'xcarchivePath'),
          runnerPath: any(named: 'runnerPath'),
          isCodesigned: any(named: 'isCodesigned'),
        ),
      ).thenAnswer((_) async => release);
      when(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          status: any(named: 'status'),
          metadata: any(named: 'metadata'),
        ),
      ).thenAnswer((_) async => {});

      when(() => doctor.iosCommandValidators).thenReturn([flutterValidator]);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
          supportedOperatingSystems: any(named: 'supportedOperatingSystems'),
        ),
      ).thenAnswer((_) async {});
      when(() => xcodeBuild.version()).thenAnswer((_) async => xcodeVersion);

      command = runWithOverrides(ReleaseIosCommand.new)
        ..testArgResults = argResults;
    });

    test('supports alpha alias', () {
      expect(command.aliases, contains('ios-alpha'));
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    test('exits when validation fails', () async {
      final exception = ValidationFailedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
          supportedOperatingSystems: any(named: 'supportedOperatingSystems'),
        ),
      ).thenThrow(exception);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(exception.exitCode.code)),
      );
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
          checkShorebirdInitialized: true,
          validators: any(named: 'validators'),
          supportedOperatingSystems: {Platform.macOS},
        ),
      ).called(1);
    });

    test('exits with explanation if force flag is used', () async {
      when(() => argResults['force']).thenReturn(true);

      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.usage.code)),
      );

      verify(() => logger.err(ReleaseCommand.forceDeprecationErrorMessage))
          .called(1);
      verify(() => logger.info(ReleaseCommand.forceDeprecationExplanation))
          .called(1);
    });

    group('when obfuscate flag is passed', () {
      setUp(() {
        when(() => argResults.rest).thenReturn(['--obfuscate']);
      });

      test('prints error and exits with usage code', () async {
        final exitCode = await runWithOverrides(command.run);

        expect(exitCode, equals(ExitCode.usage.code));
        verify(
          () => logger
              .err('Shorebird does not currently support obfuscation on iOS.'),
        ).called(1);
      });
    });

    group('when codesign is disabled', () {
      setUp(() {
        when(() => argResults['codesign']).thenReturn(false);
      });

      test('prints instructions to manually codesign', () async {
        setUpProjectRoot();
        await runWithOverrides(command.run);

        verify(
          () => logger.info(
            '''Building for device with codesigning disabled. You will have to manually codesign before deploying to device.''',
          ),
        ).called(1);
      });

      test('builds without codesigning', () async {
        setUpProjectRoot();
        await runWithOverrides(command.run);

        verify(
          () => shorebirdProcess.run(
            'flutter',
            any(
              that: containsAllInOrder(
                [
                  'build',
                  'ipa',
                  '--release',
                  '--no-codesign',
                ],
              ),
            ),
            runInShell: true,
          ),
        ).called(1);
      });

      group('when build directory has non-default structure', () {
        test('prints error and exits with code 70 if xcarchive does not exist',
            () async {
          setUpProjectRoot();
          Directory(
            p.join(
              projectRoot.path,
              'build',
              'ios',
              'archive',
              'Runner.xcarchive',
            ),
          ).deleteSync(recursive: true);

          final exitCode = await runWithOverrides(command.run);

          expect(exitCode, equals(ExitCode.software.code));
          verify(
            () => logger.err('Unable to find .xcarchive directory'),
          ).called(1);
        });

        test(
            '''prints error and exits with code 70 if .app directory does not exist''',
            () async {
          setUpProjectRoot();
          Directory(
            p.join(
              projectRoot.path,
              'build',
              'ios',
              'archive',
              'Runner.xcarchive',
              'Products',
              'Applications',
            ),
          ).deleteSync(recursive: true);

          final exitCode = await runWithOverrides(command.run);

          expect(exitCode, equals(ExitCode.software.code));
          verify(() => logger.err('Unable to find .app directory')).called(1);
        });

        test(
            '''finds .xcarchive and .app when they do not have the default "Runner" name''',
            () async {
          setUpProjectRoot();
          final archivePath = p.join(
            projectRoot.path,
            'build',
            'ios',
            'archive',
          );
          final applicationsPath = p.join(
            archivePath,
            'Runner.xcarchive',
            'Products',
            'Applications',
          );
          Directory(p.join(applicationsPath, 'Runner.app')).renameSync(
            p.join(
              applicationsPath,
              'شوربيرد | Shorebird.app',
            ),
          );
          Directory(p.join(archivePath, 'Runner.xcarchive')).renameSync(
            p.join(
              archivePath,
              'شوربيرد | Shorebird.xcarchive',
            ),
          );

          final exitCode = await runWithOverrides(command.run);

          expect(exitCode, equals(ExitCode.success.code));
        });
      });

      test('prints archive upload instructions on success', () async {
        setUpProjectRoot();
        final exitCode = await runWithOverrides(command.run);

        expect(exitCode, equals(ExitCode.success.code));
        final archivePath = p.join(
          projectRoot.path,
          'build',
          'ios',
          'archive',
          'Runner.xcarchive',
        );
        verify(
          () => logger.info(
            any(
              that: stringContainsInOrder(
                [
                  'Your next step is to submit the archive',
                  p.relative(archivePath),
                  'to the App Store using Xcode.',
                  'You can open the archive in Xcode by running',
                  'open ${p.relative(archivePath)}',
                  '''Make sure to uncheck "Manage Version and Build Number", or else shorebird will not work.''',
                ],
              ),
            ),
          ),
        ).called(1);
      });

      test('creates unsigned release artifacts', () async {
        setUpProjectRoot();
        final exitCode = await runWithOverrides(command.run);

        expect(exitCode, equals(ExitCode.success.code));

        verify(
          () => codePushClientWrapper.createIosReleaseArtifacts(
            appId: appId,
            releaseId: release.id,
            xcarchivePath: any(
              named: 'xcarchivePath',
              that: endsWith('.xcarchive'),
            ),
            runnerPath: any(named: 'runnerPath', that: endsWith('Runner.app')),
            isCodesigned: false,
          ),
        ).called(1);
      });
    });

    group('when exportOptionsPlistFromArgs throws exception', () {
      setUp(() {
        when(() => ios.exportOptionsPlistFromArgs(argResults))
            .thenThrow(ArgumentError('bad args'));
      });

      test('logs error and exits with usage code', () async {
        setUpProjectRoot();
        final exitCode = await runWithOverrides(command.run);

        expect(exitCode, equals(ExitCode.usage.code));
        verify(() => logger.err('Invalid argument(s): bad args')).called(1);
      });
    });

    group('when flutter-version is provided', () {
      const flutterVersion = '3.16.3';
      setUp(() {
        when(() => argResults['flutter-version']).thenReturn(flutterVersion);
      });

      group('when unable to determine flutter revision', () {
        final exception = Exception('oops');
        setUp(() {
          when(
            () => shorebirdFlutter.getRevisionForVersion(any()),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.software.code));
          verify(
            () => logger.err(
              '''
Unable to determine revision for Flutter version: $flutterVersion.
$exception''',
            ),
          ).called(1);
        });
      });

      group('when flutter version is not supported', () {
        setUp(() {
          when(
            () => shorebirdFlutter.getRevisionForVersion(any()),
          ).thenAnswer((_) async => null);
        });

        test('exits with code 70', () async {
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.software.code));
          verify(
            () => logger.err(
              any(that: contains('Version $flutterVersion not found.')),
            ),
          ).called(1);
        });
      });

      group('when flutter version is supported', () {
        const revision = '771d07b2cf';
        setUp(() {
          setUpProjectRoot();
          when(
            () => shorebirdFlutter.getRevisionForVersion(any()),
          ).thenAnswer((_) async => revision);
        });

        test('uses specified flutter version to build', () async {
          when(
            () => shorebirdProcess.run(
              'flutter',
              any(),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer((_) async {
            // Ensure we're using the correct flutter version.
            expect(shorebirdEnv.flutterRevision, equals(revision));
            return flutterBuildProcessResult;
          });

          await runWithOverrides(command.run);

          verify(() => shorebirdFlutter.installRevision(revision: revision))
              .called(1);
          verify(
            () => codePushClientWrapper.createRelease(
              appId: appId,
              version: version,
              flutterRevision: revision,
              platform: releasePlatform,
            ),
          ).called(1);
          verify(
            () => codePushClientWrapper.updateReleaseStatus(
              appId: appId,
              releaseId: release.id,
              platform: releasePlatform,
              status: ReleaseStatus.active,
              metadata: const UpdateReleaseMetadata(
                releasePlatform: releasePlatform,
                flutterVersionOverride: flutterVersion,
                generatedApks: false,
                environment: BuildEnvironmentMetadata(
                  operatingSystem: operatingSystem,
                  operatingSystemVersion: operatingSystemVersion,
                  shorebirdVersion: packageVersion,
                  xcodeVersion: xcodeVersion,
                ),
              ),
            ),
          ).called(1);
        });

        group('when flutter version install fails', () {
          setUp(() {
            when(
              () => shorebirdFlutter.installRevision(
                revision: any(named: 'revision'),
              ),
            ).thenThrow(Exception('oops'));
          });

          test('exits with code 70', () async {
            final result = await runWithOverrides(command.run);

            expect(result, equals(ExitCode.software.code));
            verify(
              () => shorebirdFlutter.installRevision(revision: revision),
            ).called(1);
          });
        });
      });
    });

    test('exits with code 70 when build fails with non-zero exit code',
        () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oops');

      setUpProjectRoot();
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => progress.fail(any(that: contains('Failed to build'))),
      ).called(1);
    });

    test('exits with code 70 when building fails with 0 exit code', () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(0);
      when(() => flutterBuildProcessResult.stderr).thenReturn('''
Encountered error while creating the IPA:
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found
error: exportArchive: Team "My Team" does not have permission to create "iOS App Store" provisioning profiles.
error: exportArchive: No profiles for 'com.example.co' were found
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found
''');

      setUpProjectRoot();
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => progress.fail(any(that: contains('Failed to build'))),
      ).called(1);
      verify(
        () => logger.err('''
    Communication with Apple failed
    No signing certificate "iOS Distribution" found
    Team "My Team" does not have permission to create "iOS App Store" provisioning profiles.
    No profiles for 'com.example.co' were found'''),
      ).called(1);
    });

    test('exits with code 70 when release version cannot be determined',
        () async {
      setUpProjectRoot();
      final file = File(
        p.join(
          projectRoot.path,
          'build',
          'ios',
          'archive',
          'Runner.xcarchive',
          'Info.plist',
        ),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync(emptyPlistContent);
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => logger.err(
          'Failed to determine release version from ${file.path}: '
          'Exception: Could not determine release version',
        ),
      ).called(1);
    });

    test('aborts when user opts out', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      setUpProjectRoot();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.success.code);
      verify(() => logger.info('Aborting.')).called(1);
      verifyNever(
        () => codePushClientWrapper.createIosReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          xcarchivePath:
              any(named: 'xcarchivePath', that: endsWith('.xcarchive')),
          runnerPath: any(named: 'runnerPath', that: endsWith('Runner.app')),
          isCodesigned: any(named: 'isCodesigned'),
        ),
      );
    });

    test('exits with code 70 if Info.plist does not exist', () async {
      setUpProjectRoot();
      final infoPlistFile = File(
        p.join(
          projectRoot.path,
          'build',
          'ios',
          'archive',
          'Runner.xcarchive',
          'Info.plist',
        ),
      )..deleteSync(recursive: true);

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => logger.err('No Info.plist file found at ${infoPlistFile.path}.'),
      ).called(1);
    });

    test('exits with code 70 if build directory does not exist', () async {
      setUpProjectRoot();
      Directory(p.join(projectRoot.path, 'build')).deleteSync(recursive: true);

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(() => logger.err('Unable to find .xcarchive directory')).called(1);
    });

    test('exits with code 70 if ipa build directory does not exist', () async {
      setUpProjectRoot();
      final ipaDirectory = Directory(
        p.join(projectRoot.path, 'build', 'ios', 'ipa'),
      )..deleteSync(recursive: true);

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => logger.err(
          any(
            that: stringContainsInOrder(
              [
                'Could not find ipa file',
                'No directory found at ${ipaDirectory.path}',
              ],
            ),
          ),
        ),
      ).called(1);
    });

    test('exits with code 70 if ipa file does not exist', () async {
      setUpProjectRoot();
      File(p.join(projectRoot.path, ipaPath)).deleteSync(recursive: true);

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => logger.err(
          any(
            that: stringContainsInOrder([
              'Could not find ipa file',
              'No .ipa files found in',
              p.join('build', 'ios', 'ipa'),
            ]),
          ),
        ),
      ).called(1);
    });

    test('exits with code 70 if more than one ipa file is found', () async {
      setUpProjectRoot();
      File(
        p.join(projectRoot.path, 'build/ios/ipa/Runner2.ipa'),
      ).createSync(recursive: true);

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => logger.err(
          any(
            that: stringContainsInOrder([
              'Could not find ipa file',
              'More than one .ipa file found in',
              p.join('build', 'ios', 'ipa'),
            ]),
          ),
        ),
      ).called(1);
    });

    test('succeeds when release is successful', () async {
      setUpProjectRoot();

      final exitCode = await runWithOverrides(command.run);

      verify(() => logger.success('\n✅ Published Release $version!')).called(1);
      verify(
        () => logger.info(
          any(
            that: stringContainsInOrder(
              [
                'Your next step is to upload your app to App Store Connect.',
                p.join('build', 'ios', 'ipa', 'Runner.ipa'),
              ],
            ),
          ),
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.createIosReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          xcarchivePath:
              any(named: 'xcarchivePath', that: endsWith('.xcarchive')),
          runnerPath: any(named: 'runnerPath', that: endsWith('Runner.app')),
          isCodesigned: true,
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          status: ReleaseStatus.active,
          metadata: const UpdateReleaseMetadata(
            releasePlatform: releasePlatform,
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
      ).called(1);
      expect(exitCode, ExitCode.success.code);
    });

    test('runs flutter pub get with system flutter after successful build',
        () async {
      setUpProjectRoot();

      await runWithOverrides(command.run);

      verify(
        () => shorebirdProcess.run(
          'flutter',
          ['--no-version-check', 'pub', 'get', '--offline'],
          runInShell: any(named: 'runInShell'),
          useVendedFlutter: false,
        ),
      ).called(1);
    });

    test(
        'succeeds when release is successful '
        'with flavors and target', () async {
      const flavor = 'development';
      final target = p.join('lib', 'main_development.dart');
      when(() => argResults['flavor']).thenReturn(flavor);
      when(() => argResults['target']).thenReturn(target);
      setUpProjectRoot();
      File(
        p.join(projectRoot.path, 'shorebird.yaml'),
      ).writeAsStringSync('''
app_id: productionAppId
flavors:
  development: $appId''');

      final exitCode = await runWithOverrides(command.run);

      verify(() => logger.success('\n✅ Published Release $version!')).called(1);
      verify(
        () => logger.info(
          any(
            that: stringContainsInOrder(
              [
                'Your next step is to upload your app to App Store Connect.',
                p.join('build', 'ios', 'ipa', 'Runner.ipa'),
              ],
            ),
          ),
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.createIosReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          xcarchivePath:
              any(named: 'xcarchivePath', that: endsWith('.xcarchive')),
          runnerPath: any(named: 'runnerPath', that: endsWith('Runner.app')),
          isCodesigned: true,
        ),
      ).called(1);
      expect(exitCode, ExitCode.success.code);
    });

    test('does not create new release if existing release is present',
        () async {
      when(
        () => codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
      setUpProjectRoot();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.success.code);
      verifyNever(
        () => codePushClientWrapper.createRelease(
          appId: any(named: 'appId'),
          version: any(named: 'version'),
          flutterRevision: any(named: 'flutterRevision'),
          platform: any(named: 'platform'),
        ),
      );
      verify(
        () => codePushClientWrapper.createIosReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          xcarchivePath:
              any(named: 'xcarchivePath', that: endsWith('.xcarchive')),
          runnerPath: any(named: 'runnerPath', that: endsWith('Runner.app')),
          isCodesigned: true,
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          status: ReleaseStatus.active,
          metadata: any(named: 'metadata'),
        ),
      ).called(1);
    });

    test('does not provide export options when codesign is false', () async {
      when(() => argResults['codesign']).thenReturn(false);
      setUpProjectRoot();

      await runWithOverrides(command.run);

      final capturedArgs = verify(
        () => shorebirdProcess.run(
          'flutter',
          captureAny(),
          runInShell: any(named: 'runInShell'),
        ),
      ).captured.first as List<String>;
      expect(
        capturedArgs
            .whereType<String>()
            .firstWhereOrNull((arg) => arg.contains('export-options-plist')),
        isNull,
      );
    });

    test('does not prompt if unable to accept user input', () async {
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);
      setUpProjectRoot();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(() => logger.confirm(any()));
    });
  });
}

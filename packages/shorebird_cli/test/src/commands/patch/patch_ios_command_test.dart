import 'dart:io' hide Platform;

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/executables/aot_tools.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/ios.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../mocks.dart';

void main() {
  const preLinkerFlutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
  const postLinkerFlutterRevision = 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
  const appId = 'test-app-id';
  const shorebirdYaml = ShorebirdYaml(appId: appId);
  const versionName = '1.2.3';
  const versionCode = '1';
  const version = '$versionName+$versionCode';
  const arch = 'aarch64';
  const operatingSystem = 'macOS';
  const operatingSystemVersion = '11.0.0';
  const xcodeVersion = '12.0';
  const track = DeploymentTrack.production;
  const appDisplayName = 'Test App';
  const releasePlatform = ReleasePlatform.ios;
  const platformName = 'ios';
  const elfAotSnapshotFileName = 'out.aot';
  const linkFileName = 'out.vmcode';
  const ipaPath = 'build/ios/ipa/Runner.ipa';
  const releaseArtifactFilePath = 'downloads/release.artifact';
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

  final appMetadata = AppMetadata(
    appId: appId,
    displayName: appDisplayName,
    createdAt: DateTime(2023),
    updatedAt: DateTime(2023),
  );
  const ipaArtifact = ReleaseArtifact(
    id: 0,
    releaseId: 0,
    arch: arch,
    platform: ReleasePlatform.ios,
    hash: '#',
    size: 42,
    url: 'https://example.com/release.ipa',
  );
  final preLinkerRelease = Release(
    id: 0,
    appId: appId,
    version: version,
    flutterRevision: preLinkerFlutterRevision,
    displayName: '1.2.3+1',
    platformStatuses: {ReleasePlatform.ios: ReleaseStatus.active},
    createdAt: DateTime(2023),
    updatedAt: DateTime(2023),
  );
  final postLinkerRelease = Release(
    id: 0,
    appId: appId,
    version: version,
    flutterRevision: postLinkerFlutterRevision,
    displayName: '1.2.4+1',
    platformStatuses: {ReleasePlatform.ios: ReleaseStatus.active},
    createdAt: DateTime(2023),
    updatedAt: DateTime(2023),
  );

  group(PatchIosCommand, () {
    late AotTools aotTools;
    late ArgResults argResults;
    late ArtifactManager artifactManager;
    late Auth auth;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory flutterDirectory;
    late Directory shorebirdRoot;
    late Directory projectRoot;
    late EngineConfig engineConfig;
    late File genSnapshotFile;
    late File analyzeSnapshotFile;
    late File releaseArtifactFile;
    late ShorebirdArtifacts shorebirdArtifacts;
    late Doctor doctor;
    late Ios ios;
    late IosArchiveDiffer archiveDiffer;
    late Progress progress;
    late Logger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late PatchDiffChecker patchDiffChecker;
    late Platform platform;
    late ShorebirdProcessResult aotBuildProcessResult;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterPubGetProcessResult;
    late http.Client httpClient;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdValidator shorebirdValidator;
    late XcodeBuild xcodeBuild;
    late PatchIosCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          aotToolsRef.overrideWith(() => aotTools),
          artifactManagerRef.overrideWith(() => artifactManager),
          authRef.overrideWith(() => auth),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          engineConfigRef.overrideWith(() => engineConfig),
          iosRef.overrideWith(() => ios),
          shorebirdArtifactsRef.overrideWith(() => shorebirdArtifacts),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          patchDiffCheckerRef.overrideWith(() => patchDiffChecker),
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
      File(
        p.join(
          projectRoot.path,
          'build',
          'ios',
          'archive',
          'Runner.xcarchive',
          'Products',
          'Applications',
          'Runner.app',
          'Frameworks',
          'App.framework',
          'App',
        ),
      ).createSync(recursive: true);
      File(p.join(projectRoot.path, ipaPath)).createSync(recursive: true);
    }

    void setUpProjectRootArtifacts() {
      // Create a second app.dill for coverage of newestAppDill file.
      File(
        p.join(
          projectRoot.path,
          '.dart_tool',
          'flutter_build',
          'subdir',
          'app.dill',
        ),
      ).createSync(recursive: true);
      File(
        p.join(projectRoot.path, '.dart_tool', 'flutter_build', 'app.dill'),
      ).createSync(recursive: true);
      File(
        p.join(projectRoot.path, 'build', elfAotSnapshotFileName),
      ).createSync(recursive: true);
      File(
        p.join(projectRoot.path, 'build', linkFileName),
      ).createSync(recursive: true);
    }

    setUpAll(() {
      registerFallbackValue(CreatePatchMetadata.forTest());
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(FileSetDiff.empty());
      registerFallbackValue(ReleasePlatform.ios);
      registerFallbackValue(Uri.parse('https://example.com'));
      registerFallbackValue(FakeBaseRequest());
      registerFallbackValue(FakeShorebirdProcess());
      registerFallbackValue(DeploymentTrack.production);
    });

    setUp(() {
      argResults = MockArgResults();
      artifactManager = MockArtifactManager();
      aotTools = MockAotTools();
      auth = MockAuth();
      codePushClientWrapper = MockCodePushClientWrapper();
      doctor = MockDoctor();
      engineConfig = MockEngineConfig();
      ios = MockIos();
      shorebirdArtifacts = MockShorebirdArtifacts();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      projectRoot = Directory.systemTemp.createTempSync();
      flutterDirectory = Directory(
        p.join(shorebirdRoot.path, 'bin', 'cache', 'flutter'),
      );
      genSnapshotFile = File(
        p.join(
          flutterDirectory.path,
          'bin',
          'cache',
          'artifacts',
          'engine',
          'ios-release',
          'gen_snapshot_arm64',
        ),
      );
      analyzeSnapshotFile = File(
        p.join(
          flutterDirectory.path,
          'bin',
          'cache',
          'artifacts',
          'engine',
          'android-arm-release',
          'darwin-x64',
          'analyze_snapshot',
        ),
      )..createSync(recursive: true);
      releaseArtifactFile =
          File(p.join(projectRoot.path, releaseArtifactFilePath))
            ..createSync(recursive: true);
      archiveDiffer = MockIosArchiveDiffer();
      progress = MockProgress();
      logger = MockLogger();
      platform = MockPlatform();
      aotBuildProcessResult = MockProcessResult();
      flutterBuildProcessResult = MockProcessResult();
      flutterPubGetProcessResult = MockProcessResult();
      httpClient = MockHttpClient();
      operatingSystemInterface = MockOperatingSystemInterface();
      patchDiffChecker = MockPatchDiffChecker();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      flutterValidator = MockShorebirdFlutterValidator();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdValidator = MockShorebirdValidator();
      xcodeBuild = MockXcodeBuild();

      when(() => argResults['allow-asset-diffs']).thenReturn(false);
      when(() => argResults['allow-native-diffs']).thenReturn(false);
      when(() => argResults['arch']).thenReturn(arch);
      when(() => argResults['dry-run']).thenReturn(false);
      when(() => argResults['codesign']).thenReturn(true);
      when(() => argResults['staging']).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(true);
      when(
        () => aotTools.link(
          base: any(named: 'base'),
          patch: any(named: 'patch'),
          analyzeSnapshot: any(named: 'analyzeSnapshot'),
          genSnapshot: any(named: 'genSnapshot'),
          kernel: any(named: 'kernel'),
          workingDirectory: any(named: 'workingDirectory'),
          outputPath: any(named: 'outputPath'),
        ),
      ).thenAnswer((_) async => null);
      when(() => aotTools.isGeneratePatchDiffBaseSupported())
          .thenAnswer((_) async => false);
      when(
        () => aotTools.generatePatchDiffBase(
          releaseSnapshot: any(named: 'releaseSnapshot'),
          analyzeSnapshotPath: any(named: 'analyzeSnapshotPath'),
        ),
      ).thenAnswer((_) async => File(''));
      when(() => artifactManager.downloadFile(any()))
          .thenAnswer((_) async => releaseArtifactFile);
      when(
        () => artifactManager.extractZip(
          zipFile: any(named: 'zipFile'),
          outputDirectory: any(named: 'outputDirectory'),
        ),
      ).thenAnswer((invocation) async {
        final outputDirectory =
            invocation.namedArguments[#outputDirectory] as Directory;
        File(
          p.join(
            outputDirectory.path,
            'Products',
            'Applications',
            'App.app',
            'Frameworks',
            'App.framework',
            'App',
          ),
        ).createSync(recursive: true);
      });
      when(
        () => artifactManager.createDiff(
          releaseArtifactPath: any(named: 'releaseArtifactPath'),
          patchArtifactPath: any(named: 'patchArtifactPath'),
        ),
      ).thenAnswer((_) async => '');
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
      ).thenAnswer((_) async => appMetadata);
      when(
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => preLinkerRelease);
      when(
        () => codePushClientWrapper.getReleaseArtifact(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async => ipaArtifact);
      when(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          track: any(named: 'track'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
          metadata: any(named: 'metadata'),
        ),
      ).thenAnswer((_) async {});
      when(() => doctor.iosCommandValidators).thenReturn([flutterValidator]);
      when(() => engineConfig.localEngine).thenReturn(null);
      when(
        () => ios.exportOptionsPlistFromArgs(argResults),
      ).thenReturn(File('.'));
      when(flutterValidator.validate).thenAnswer((_) async => []);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => operatingSystemInterface.which('flutter'),
      ).thenReturn('/path/to/flutter');
      when(() => platform.operatingSystem).thenReturn(operatingSystem);
      when(() => platform.operatingSystemVersion)
          .thenReturn(operatingSystemVersion);
      when(() => platform.environment).thenReturn({});
      when(() => platform.script).thenReturn(shorebirdRoot.uri);
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
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
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(
        () => shorebirdArtifacts.getArtifactPath(
          artifact: ShorebirdArtifact.genSnapshot,
        ),
      ).thenReturn(genSnapshotFile.path);
      when(
        () => shorebirdArtifacts.getArtifactPath(
          artifact: ShorebirdArtifact.analyzeSnapshot,
        ),
      ).thenReturn(analyzeSnapshotFile.path);
      when(() => shorebirdEnv.flutterRevision)
          .thenReturn(preLinkerFlutterRevision);
      when(() => shorebirdEnv.isRunningOnCI).thenReturn(false);
      when(
        () => shorebirdFlutter.installRevision(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => aotBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => flutterBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(() => flutterPubGetProcessResult.exitCode)
          .thenReturn(ExitCode.success.code);
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
      when(
        () => shorebirdProcess.run(
          any(that: endsWith('gen_snapshot_arm64')),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => aotBuildProcessResult);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
          supportedOperatingSystems: any(named: 'supportedOperatingSystems'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifact: any(named: 'releaseArtifact'),
          archiveDiffer: archiveDiffer,
          allowAssetChanges: any(named: 'allowAssetChanges'),
          allowNativeChanges: any(named: 'allowNativeChanges'),
        ),
      ).thenAnswer(
        (_) async => DiffStatus(
          hasAssetChanges: false,
          hasNativeChanges: false,
        ),
      );
      when(() => xcodeBuild.version()).thenAnswer((_) async => xcodeVersion);

      command = runWithOverrides(
        () => PatchIosCommand(archiveDiffer: archiveDiffer),
      )..testArgResults = argResults;
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
          validators: [flutterValidator],
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

      verify(() => logger.err(PatchCommand.forceDeprecationErrorMessage))
          .called(1);
      verify(() => logger.info(PatchCommand.forceDeprecationExplanation))
          .called(1);
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

    test('exits with code 70 when building fails', () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oops');

      setUpProjectRoot();
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
    });

    test('exits with code 70 when building fails (due to BuildException)',
        () async {
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

    group('when build directory has non-default structure', () {
      test('exits with code 70 if xcarchive is not found', () async {
        setUpProjectRoot();
        setUpProjectRootArtifacts();
        Directory(
          p.join(projectRoot.path, 'build'),
        ).deleteSync(recursive: true);

        final exitCode = await runWithOverrides(command.run);

        expect(exitCode, equals(ExitCode.software.code));
        verify(
          () => logger.err(
            any(that: contains('Unable to find .xcarchive directory')),
          ),
        ).called(1);
      });

      test('prints error and exits with code 70 if Info.plist does not exist',
          () async {
        setUpProjectRoot();
        setUpProjectRootArtifacts();
        final plistPath = p.join(
          projectRoot.path,
          'build',
          'ios',
          'archive',
          'Runner.xcarchive',
          'Info.plist',
        );
        File(plistPath).deleteSync();

        final exitCode = await runWithOverrides(command.run);

        expect(exitCode, equals(ExitCode.software.code));
        verify(
          () => logger.err('No Info.plist file found at $plistPath.'),
        ).called(1);
      });

      test('finds xcarchive that has been renamed from Runner', () async {
        setUpProjectRoot();
        setUpProjectRootArtifacts();
        Directory(
          p.join(
            projectRoot.path,
            'build',
            'ios',
            'archive',
            'Runner.xcarchive',
          ),
        ).renameSync(
          p.join(
            projectRoot.path,
            'build',
            'ios',
            'archive',
            'شوربيرد | Shorebird.xcarchive',
          ),
        );

        final exitCode = await runWithOverrides(command.run);

        expect(exitCode, equals(ExitCode.success.code));
      });
    });

    test(
        '''exits with code 70 if release does not exist for the ios platform''',
        () async {
      when(
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer(
        (_) async => Release(
          id: 0,
          appId: appId,
          version: version,
          flutterRevision: preLinkerFlutterRevision,
          displayName: '1.2.3+1',
          platformStatuses: {ReleasePlatform.android: ReleaseStatus.active},
          createdAt: DateTime(2023),
          updatedAt: DateTime(2023),
        ),
      );
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.software.code);
      verify(() => logger.err('No iOS release found for 1.2.3+1.')).called(1);
    });

    test(
        '''exits with code 70 if release is in draft state for the ios platform''',
        () async {
      when(
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer(
        (_) async => Release(
          id: 0,
          appId: appId,
          version: version,
          flutterRevision: preLinkerFlutterRevision,
          displayName: '1.2.3+1',
          platformStatuses: {ReleasePlatform.ios: ReleaseStatus.draft},
          createdAt: DateTime(2023),
          updatedAt: DateTime(2023),
        ),
      );
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.software.code);
      verify(
        () => logger.err('''
Release 1.2.3+1 is in an incomplete state. It's possible that the original release was terminated or failed to complete.
Please re-run the release command for this version or create a new release.'''),
      ).called(1);
    });

    test('proceeds if release is in draft state for a non-ios platform',
        () async {
      when(
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer(
        (_) async => Release(
          id: 0,
          appId: appId,
          version: version,
          flutterRevision: preLinkerFlutterRevision,
          displayName: '1.2.3+1',
          platformStatuses: {
            ReleasePlatform.android: ReleaseStatus.draft,
            ReleasePlatform.ios: ReleaseStatus.active,
          },
          createdAt: DateTime(2023),
          updatedAt: DateTime(2023),
        ),
      );
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
    });

    test(
        '''switches to release flutter revision when shorebird flutter revision does not match''',
        () async {
      const otherRevision = 'other-revision';
      when(() => shorebirdEnv.flutterRevision).thenReturn(otherRevision);

      // If a release version is not specified as a command argument, we
      // build the app with the default Flutter revision to determine the
      // release version. We then build the app with the release Flutter
      // revision to determine the release version.
      var hasBuiltToDetermineReleaseVersion = false;
      var hasRunGenSnapshotToDetermineReleaseVersion = false;
      when(
        () => shorebirdProcess.run(
          'flutter',
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async {
        if (!hasBuiltToDetermineReleaseVersion) {
          hasBuiltToDetermineReleaseVersion = true;
          return flutterBuildProcessResult;
        }

        // Ensure we're using the correct flutter revision.
        expect(shorebirdEnv.flutterRevision, equals(preLinkerFlutterRevision));
        return flutterBuildProcessResult;
      });
      when(
        () => shorebirdProcess.run(
          any(that: endsWith('gen_snapshot_arm64')),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async {
        if (!hasRunGenSnapshotToDetermineReleaseVersion) {
          hasRunGenSnapshotToDetermineReleaseVersion = true;
          return aotBuildProcessResult;
        }

        // Ensure we're using the correct flutter revision.
        expect(shorebirdEnv.flutterRevision, equals(preLinkerFlutterRevision));
        return aotBuildProcessResult;
      });
      when(
        () => aotTools.link(
          base: any(named: 'base'),
          patch: any(named: 'patch'),
          analyzeSnapshot: any(named: 'analyzeSnapshot'),
          genSnapshot: any(named: 'genSnapshot'),
          kernel: any(named: 'kernel'),
          workingDirectory: any(named: 'workingDirectory'),
          outputPath: any(named: 'outputPath'),
        ),
      ).thenAnswer((_) async {
        // Ensure we're using the correct flutter revision.
        expect(shorebirdEnv.flutterRevision, equals(preLinkerFlutterRevision));
        return null;
      });

      setUpProjectRoot();
      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.success.code);

      when(
        () => shorebirdFlutter.installRevision(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async {});
      verify(
        () => logger.info(
          any(
            that: stringContainsInOrder([
              '''The release you are trying to patch was built with a different version of Flutter.''',
              'Release Flutter Revision: ${preLinkerRelease.flutterRevision}',
              'Current Flutter Revision: $otherRevision',
            ]),
          ),
        ),
      ).called(1);
    });

    group('when release-version option is provided', () {
      const customReleaseVersion = 'custom-release-version';

      setUp(() {
        when(
          () => argResults['release-version'],
        ).thenReturn(customReleaseVersion);
      });

      test('does not extract release version from archive', () async {
        setUpProjectRoot();
        setUpProjectRootArtifacts();
        await runWithOverrides(command.run);

        verify(
          () => codePushClientWrapper.getRelease(
            appId: appId,
            releaseVersion: customReleaseVersion,
          ),
        ).called(1);
      });

      test('exits with code 70 if xcarchive is not found', () async {
        setUpProjectRoot();
        setUpProjectRootArtifacts();
        Directory(
          p.join(projectRoot.path, 'build'),
        ).deleteSync(recursive: true);

        final exitCode = await runWithOverrides(command.run);

        expect(exitCode, equals(ExitCode.software.code));
        verify(
          () => logger.err(
            any(that: contains('Unable to find .xcarchive directory')),
          ),
        ).called(1);
      });

      test('exits with code 70 if build fails', () async {
        when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
        when(() => flutterBuildProcessResult.stderr).thenReturn('oops');

        setUpProjectRoot();
        setUpProjectRootArtifacts();
        final exitCode = await runWithOverrides(command.run);
        expect(exitCode, ExitCode.software.code);
      });

      test('only builds once if release uses different flutter revision',
          () async {
        const otherRevision = 'other-revision';
        when(() => shorebirdEnv.flutterRevision).thenReturn(otherRevision);

        setUpProjectRoot();
        setUpProjectRootArtifacts();
        final exitCode = await runWithOverrides(command.run);
        expect(exitCode, ExitCode.success.code);

        verify(
          () => shorebirdProcess.run(
            'flutter',
            any(
              that: containsAll([
                'build',
                'ipa',
                '--release',
              ]),
            ),
            runInShell: any(named: 'runInShell'),
          ),
        ).called(1);
      });
    });

    test('exits with code 70 when release version cannot be determined',
        () async {
      setUpProjectRoot();
      setUpProjectRootArtifacts();
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

    test('prints release version when detected', () async {
      setUpProjectRoot();
      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verify(() => logger.info('Detected release version 1.2.3+1')).called(1);
    });

    test('aborts when user opts out', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
      verify(() => logger.info('Aborting.')).called(1);
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
        setUpProjectRoot();
        setUpProjectRootArtifacts();

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.software.code));
        verify(
          () => shorebirdFlutter.installRevision(
            revision: preLinkerFlutterRevision,
          ),
        ).called(1);
      });
    });

    test('throws error when creating aot snapshot fails', () async {
      const error = 'oops something went wrong';
      when(() => aotBuildProcessResult.exitCode).thenReturn(1);
      when(() => aotBuildProcessResult.stderr).thenReturn(error);
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      verify(
        () => progress.fail('Exception: Failed to create snapshot: $error'),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test(
        '''exits with code 0 if zipAndConfirmUnpatchableDiffsIfNecessary throws UserCancelledException''',
        () async {
      when(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifact: any(named: 'releaseArtifact'),
          archiveDiffer: archiveDiffer,
          allowAssetChanges: any(named: 'allowAssetChanges'),
          allowNativeChanges: any(named: 'allowNativeChanges'),
        ),
      ).thenThrow(UserCancelledException());
      setUpProjectRoot();
      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifact: releaseArtifactFile,
          archiveDiffer: archiveDiffer,
          allowAssetChanges: false,
          allowNativeChanges: false,
        ),
      ).called(1);
      verifyNever(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          track: any(named: 'track'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
          metadata: any(named: 'metadata'),
        ),
      );
    });

    test('exits with code 70 if release artifact fails to download', () async {
      setUpProjectRoot();
      setUpProjectRootArtifacts();

      releaseArtifactFile.deleteSync();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => progress.fail('Exception: Failed to download release artifact'),
      ).called(1);
    });

    group('when release artifact fails to extract', () {
      setUp(() {
        setUpProjectRoot();
        setUpProjectRootArtifacts();

        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer((invocation) async {});
      });

      test('prints error message and exits with code 70', () async {
        final exitCode = await runWithOverrides(command.run);

        expect(exitCode, equals(ExitCode.software.code));
        verify(
          () => logger.err('Unable to find release artifact .app directory'),
        ).called(1);
      });
    });

    test(
        '''exits with code 70 if zipAndConfirmUnpatchableDiffsIfNecessary throws UnpatchableChangeException''',
        () async {
      when(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifact: any(named: 'releaseArtifact'),
          archiveDiffer: archiveDiffer,
          allowAssetChanges: any(named: 'allowAssetChanges'),
          allowNativeChanges: any(named: 'allowNativeChanges'),
        ),
      ).thenThrow(UnpatchableChangeException());
      setUpProjectRoot();
      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifact: releaseArtifactFile,
          archiveDiffer: archiveDiffer,
          allowAssetChanges: false,
          allowNativeChanges: false,
        ),
      ).called(1);
      verifyNever(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          track: any(named: 'track'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
          metadata: any(named: 'metadata'),
        ),
      );
    });

    group('when the engine revision is pre-linker', () {
      setUp(() {
        setUpProjectRoot();
        setUpProjectRootArtifacts();
      });

      test('we do not attempt to link the AOT file', () async {
        await runWithOverrides(command.run);

        verifyNever(
          () => aotTools.link(
            base: any(named: 'base'),
            patch: any(named: 'patch'),
            analyzeSnapshot: any(named: 'analyzeSnapshot'),
            genSnapshot: any(named: 'genSnapshot'),
            kernel: any(named: 'kernel'),
            workingDirectory: any(named: 'workingDirectory'),
            outputPath: any(named: 'outputPath'),
          ),
        );
        verifyNever(() => aotTools.isGeneratePatchDiffBaseSupported());
      });
    });

    group('when the engine revision supports the linker', () {
      setUp(() {
        setUpProjectRoot();
        setUpProjectRootArtifacts();
        when(
          () => codePushClientWrapper.getRelease(
            appId: any(named: 'appId'),
            releaseVersion: any(named: 'releaseVersion'),
          ),
        ).thenAnswer((_) async => postLinkerRelease);
      });

      group('when using a local engine build', () {
        setUp(() {
          when(() => engineConfig.localEngine).thenReturn('engine');
        });

        test('attempts to link', () async {
          await runWithOverrides(command.run);

          verify(
            () => aotTools.link(
              base: any(named: 'base'),
              patch: any(named: 'patch'),
              analyzeSnapshot: any(named: 'analyzeSnapshot'),
              genSnapshot: any(named: 'genSnapshot'),
              kernel: any(named: 'kernel'),
              workingDirectory: any(named: 'workingDirectory'),
              outputPath: any(named: 'outputPath'),
            ),
          ).called(1);
        });
      });

      test('we attempt to link the AOT file', () async {
        await runWithOverrides(command.run);
        verify(
          () => aotTools.link(
            base: any(named: 'base'),
            patch: any(named: 'patch'),
            analyzeSnapshot: any(named: 'analyzeSnapshot'),
            genSnapshot: any(named: 'genSnapshot'),
            kernel: any(named: 'kernel'),
            workingDirectory: any(named: 'workingDirectory'),
            outputPath: any(named: 'outputPath'),
          ),
        ).called(1);
      });

      group('when patch AOT file is not found', () {
        test('exits with code 70', () async {
          final patch = File(
            p.join(projectRoot.path, 'build', elfAotSnapshotFileName),
          )..deleteSync(recursive: true);

          final exitCode = await runWithOverrides(command.run);

          expect(exitCode, equals(ExitCode.software.code));
          verify(
            () => logger.err('Unable to find patch AOT file at ${patch.path}'),
          ).called(1);
        });
      });

      group('when analyze snapshot is not found', () {
        setUp(() {
          analyzeSnapshotFile.deleteSync(recursive: true);
        });

        test('exits with code 70', () async {
          final exitCode = await runWithOverrides(command.run);

          expect(exitCode, equals(ExitCode.software.code));
          verify(
            () => logger.err(
              'Unable to find analyze_snapshot at ${analyzeSnapshotFile.path}',
            ),
          ).called(1);
        });
      });

      group('when linking fails', () {
        final exception = Exception('failed to link');
        setUp(() {
          when(
            () => aotTools.link(
              base: any(named: 'base'),
              patch: any(named: 'patch'),
              analyzeSnapshot: any(named: 'analyzeSnapshot'),
              genSnapshot: any(named: 'genSnapshot'),
              kernel: any(named: 'kernel'),
              workingDirectory: any(named: 'workingDirectory'),
              outputPath: any(named: 'outputPath'),
            ),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final exitCode = await runWithOverrides(command.run);

          expect(exitCode, equals(ExitCode.software.code));
          verify(
            () => progress.fail('Failed to link AOT files: $exception'),
          ).called(1);
        });
      });

      group('when aot_tools returns a low link percentage', () {
        setUp(() {
          when(
            () => aotTools.link(
              base: any(named: 'base'),
              patch: any(named: 'patch'),
              analyzeSnapshot: any(named: 'analyzeSnapshot'),
              genSnapshot: any(named: 'genSnapshot'),
              kernel: any(named: 'kernel'),
              workingDirectory: any(named: 'workingDirectory'),
              outputPath: any(named: 'outputPath'),
            ),
          ).thenAnswer((_) async => PatchIosCommand.minLinkPercentage - 1);
        });

        test('logs a warning', () async {
          await runWithOverrides(command.run);
          verify(
            () => logger.warn(
              PatchIosCommand.lowLinkPercentageWarning(
                PatchIosCommand.minLinkPercentage - 1,
              ),
            ),
          ).called(1);
        });
      });
    });

    group('when aot-tools supports generating patch diff base', () {
      const diffPath = 'path/to/diff';
      setUp(() {
        setUpProjectRoot();
        setUpProjectRootArtifacts();

        when(
          () => codePushClientWrapper.getRelease(
            appId: any(named: 'appId'),
            releaseVersion: any(named: 'releaseVersion'),
          ),
        ).thenAnswer((_) async => postLinkerRelease);
        when(() => aotTools.isGeneratePatchDiffBaseSupported())
            .thenAnswer((_) async => true);
        when(
          () => artifactManager.createDiff(
            releaseArtifactPath: any(named: 'releaseArtifactPath'),
            patchArtifactPath: any(named: 'patchArtifactPath'),
          ),
        ).thenAnswer((_) async => diffPath);
      });

      group('when generatePatchDiffBase fails', () {
        const errorMessage = 'oops something went wrong';
        setUp(() {
          when(
            () => aotTools.generatePatchDiffBase(
              analyzeSnapshotPath: any(named: 'analyzeSnapshotPath'),
              releaseSnapshot: any(named: 'releaseSnapshot'),
            ),
          ).thenThrow(Exception(errorMessage));
        });

        test('prints error and exits with code 70', () async {
          final result = await runWithOverrides(command.run);

          expect(result, equals(ExitCode.software.code));
          verify(() => progress.fail('Exception: $errorMessage')).called(1);
        });
      });

      test('generates diff base and publishes the appropriate patch', () async {
        const linkPercentage = 99.9;
        when(
          () => aotTools.link(
            base: any(named: 'base'),
            patch: any(named: 'patch'),
            analyzeSnapshot: any(named: 'analyzeSnapshot'),
            genSnapshot: any(named: 'genSnapshot'),
            kernel: any(named: 'kernel'),
            workingDirectory: any(named: 'workingDirectory'),
            outputPath: any(named: 'outputPath'),
          ),
        ).thenAnswer(
          (_) async => linkPercentage,
        );
        await runWithOverrides(command.run);
        verify(
          () => codePushClientWrapper.publishPatch(
            appId: appId,
            releaseId: postLinkerRelease.id,
            platform: releasePlatform,
            track: track,
            patchArtifactBundles: any(
              named: 'patchArtifactBundles',
              that: isA<Map<Arch, PatchArtifactBundle>>()
                  .having((e) => e[Arch.arm64]!.path, 'patch path', diffPath),
            ),
            metadata: const CreatePatchMetadata(
              releasePlatform: releasePlatform,
              usedIgnoreAssetChangesFlag: false,
              hasAssetChanges: false,
              usedIgnoreNativeChangesFlag: false,
              hasNativeChanges: false,
              linkPercentage: linkPercentage,
              environment: BuildEnvironmentMetadata(
                shorebirdVersion: packageVersion,
                operatingSystem: operatingSystem,
                operatingSystemVersion: operatingSystemVersion,
                xcodeVersion: xcodeVersion,
              ),
            ),
          ),
        ).called(1);
      });
    });

    test('does not create patch on --dry-run', () async {
      when(() => argResults['dry-run']).thenReturn(true);
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(
        () => codePushClientWrapper.createPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          metadata: any(named: 'metadata'),
        ),
      );
      verify(() => logger.info('No issues detected.')).called(1);
    });

    test(
        '''forwards allow-asset-diffs and allow-native-diffs to patch diff checker''',
        () async {
      setUpProjectRoot();
      setUpProjectRootArtifacts();

      when(() => argResults['allow-asset-diffs']).thenReturn(true);
      when(() => argResults['allow-native-diffs']).thenReturn(true);

      await runWithOverrides(command.run);

      verify(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifact: any(named: 'releaseArtifact'),
          archiveDiffer: archiveDiffer,
          allowAssetChanges: true,
          allowNativeChanges: true,
        ),
      ).called(1);

      when(() => argResults['allow-asset-diffs']).thenReturn(false);
      when(() => argResults['allow-native-diffs']).thenReturn(false);

      await runWithOverrides(command.run);

      verify(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifact: any(named: 'releaseArtifact'),
          archiveDiffer: archiveDiffer,
          allowAssetChanges: false,
          allowNativeChanges: false,
        ),
      ).called(1);
    });

    test('reports when patch has asset and native changes', () async {
      when(() => argResults['allow-asset-diffs']).thenReturn(true);
      when(() => argResults['allow-native-diffs']).thenReturn(true);
      when(() => archiveDiffer.containsPotentiallyBreakingAssetDiffs(any()))
          .thenReturn(true);
      when(() => archiveDiffer.containsPotentiallyBreakingNativeDiffs(any()))
          .thenReturn(true);
      when(() => archiveDiffer.changedFiles(any(), any()))
          .thenAnswer((_) async => FileSetDiff.empty());
      when(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifact: any(named: 'releaseArtifact'),
          archiveDiffer: archiveDiffer,
          allowAssetChanges: any(named: 'allowAssetChanges'),
          allowNativeChanges: any(named: 'allowNativeChanges'),
        ),
      ).thenAnswer(
        (_) async => DiffStatus(
          hasAssetChanges: true,
          hasNativeChanges: true,
        ),
      );

      setUpProjectRoot();
      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => codePushClientWrapper.publishPatch(
          appId: appId,
          releaseId: preLinkerRelease.id,
          platform: releasePlatform,
          track: track,
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
          metadata: any(
            named: 'metadata',
            that: isA<CreatePatchMetadata>()
                .having(
                  (m) => m.releasePlatform,
                  'releasePlatform',
                  releasePlatform,
                )
                .having(
                  (m) => m.hasAssetChanges,
                  'hasAssetChanges',
                  true,
                )
                .having(
                  (m) => m.hasNativeChanges,
                  'hasNativeChanges',
                  true,
                ),
          ),
        ),
      ).called(1);
    });

    test('succeeds when patch is successful (production)', () async {
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      verify(
        () => logger.info(
          any(
            that: contains(
              '''
🕹️  Platform: ${lightCyan.wrap(platformName)} ${lightCyan.wrap('[aarch64 (0 B)]')}
🟢 Track: ${lightCyan.wrap('Production')}''',
            ),
          ),
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.publishPatch(
          appId: appId,
          releaseId: preLinkerRelease.id,
          platform: releasePlatform,
          track: track,
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
          metadata: any(named: 'metadata'),
        ),
      ).called(1);

      // Verify that an export options plist was provided to the build ipa
      // command.
      const exportOptionsPlistArgName = 'export-options-plist';
      final capturedArgs = verify(
        () => shorebirdProcess.run(
          'flutter',
          captureAny(),
          runInShell: any(named: 'runInShell'),
        ),
      ).captured.first as List<String>;
      final exportOptionsPlistArg = capturedArgs
          .whereType<String>()
          .firstWhereOrNull((arg) => arg.contains(exportOptionsPlistArgName));
      expect(exportOptionsPlistArg, isNotNull);

      expect(exitCode, ExitCode.success.code);
    });

    test('succeeds when patch is successful (staging)', () async {
      when(() => argResults['staging']).thenReturn(true);
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      verify(
        () => logger.info(
          any(
            that: contains(
              '''
🕹️  Platform: ${lightCyan.wrap(platformName)} ${lightCyan.wrap('[aarch64 (0 B)]')}
🟠 Track: ${lightCyan.wrap('Staging')}''',
            ),
          ),
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.publishPatch(
          appId: appId,
          releaseId: preLinkerRelease.id,
          platform: releasePlatform,
          track: DeploymentTrack.staging,
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
          metadata: any(named: 'metadata'),
        ),
      ).called(1);
      expect(exitCode, ExitCode.success.code);
    });

    test('runs flutter pub get with system flutter after successful build',
        () async {
      setUpProjectRoot();
      setUpProjectRootArtifacts();

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

    test('forwards codesign to flutter build', () async {
      when(() => argResults['codesign']).thenReturn(false);
      setUpProjectRoot();
      setUpProjectRootArtifacts();
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

    test('does not provide export options when codesign is false', () async {
      when(() => argResults['codesign']).thenReturn(false);
      setUpProjectRoot();
      setUpProjectRootArtifacts();

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

    test('succeeds when patch is successful with flavors and target', () async {
      const flavor = 'development';
      const target = './lib/main_development.dart';
      when(() => argResults['flavor']).thenReturn(flavor);
      when(() => argResults['target']).thenReturn(target);
      setUpProjectRoot();
      File(
        p.join(projectRoot.path, 'shorebird.yaml'),
      ).writeAsStringSync('''
app_id: productionAppId
flavors:
  development: $appId''');
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
      verify(
        () => codePushClientWrapper.publishPatch(
          appId: appId,
          releaseId: preLinkerRelease.id,
          platform: releasePlatform,
          track: track,
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
          metadata: const CreatePatchMetadata(
            releasePlatform: releasePlatform,
            usedIgnoreAssetChangesFlag: false,
            hasAssetChanges: false,
            usedIgnoreNativeChangesFlag: false,
            hasNativeChanges: false,
            environment: BuildEnvironmentMetadata(
              shorebirdVersion: packageVersion,
              operatingSystem: operatingSystem,
              operatingSystemVersion: operatingSystemVersion,
              xcodeVersion: xcodeVersion,
            ),
          ),
        ),
      ).called(1);
    });

    test('succeeds when patch is successful using custom base_url', () async {
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      const baseUrl = 'https://example.com';
      File(
        p.join(projectRoot.path, 'shorebird.yaml'),
      ).writeAsStringSync(
        '''
app_id: $appId
base_url: $baseUrl''',
      );
      await runWithOverrides(command.run);
    });

    test('does not prompt if running on CI', () async {
      when(() => shorebirdEnv.isRunningOnCI).thenReturn(true);
      setUpProjectRoot();
      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(() => logger.confirm(any()));
    });
  });
}

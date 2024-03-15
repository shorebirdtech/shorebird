import 'dart:io';

import 'package:args/args.dart';
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
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(PatchIosFrameworkCommand, () {
    const appDisplayName = 'Test App';
    const appId = 'test-app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const versionName = '1.2.3';
    const versionCode = '1';
    const track = DeploymentTrack.production;
    const version = '$versionName+$versionCode';
    const linkFileName = 'out.vmcode';
    const elfAotSnapshotFileName = 'out.aot';
    const postLinkerFlutterRevision =
        'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
    const preLinkerFlutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
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
    const arch = 'aarch64';
    const xcframeworkArtifact = ReleaseArtifact(
      id: 0,
      releaseId: 0,
      arch: arch,
      platform: ReleasePlatform.ios,
      hash: '#',
      size: 42,
      url: 'https://example.com/release.xcframework',
    );
    final preLinkerRelease = Release(
      id: 0,
      appId: appId,
      version: version,
      flutterRevision: preLinkerFlutterRevision,
      displayName: '1.2.3+1',
      platformStatuses: {},
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

    late File releaseArtifactFile;

    late AotTools aotTools;
    late ArgResults argResults;
    late ArtifactManager artifactManager;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory shorebirdRoot;
    late Directory projectRoot;
    late Directory flutterDirectory;
    late EngineConfig engineConfig;
    late File analyzeSnapshotFile;
    late File genSnapshotFile;
    late ShorebirdArtifacts shorebirdArtifacts;
    late Doctor doctor;
    late IosArchiveDiffer archiveDiffer;
    late PatchDiffChecker patchDiffChecker;
    late Platform platform;
    late Auth auth;
    late OperatingSystemInterface operatingSystemInterface;
    late Logger logger;
    late Progress progress;
    late ShorebirdProcessResult aotBuildProcessResult;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterPubGetProcessResult;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdValidator shorebirdValidator;
    late PatchIosFrameworkCommand command;

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
          shorebirdArtifactsRef.overrideWith(() => shorebirdArtifacts),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          patchDiffCheckerRef.overrideWith(() => patchDiffChecker),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
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
      File(p.join(projectRoot.path, 'build', elfAotSnapshotFileName))
          .createSync(
        recursive: true,
      );
      Directory(
        p.join(
          projectRoot.path,
          'build',
          'ios',
          'framework',
          'Release',
          'App.xcframework',
        ),
      ).createSync(
        recursive: true,
      );
      File(
        p.join(projectRoot.path, 'build', linkFileName),
      ).createSync(recursive: true);
    }

    void setUpProjectRoot() {
      File(
        p.join(projectRoot.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      File(
        p.join(projectRoot.path, 'shorebird.yaml'),
      ).writeAsStringSync('app_id: $appId');
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(FileSetDiff.empty());
      registerFallbackValue(ReleasePlatform.ios);
      registerFallbackValue(Uri.parse('https://example.com'));
      registerFallbackValue(DeploymentTrack.production);
    });

    setUp(() {
      aotTools = MockAotTools();
      argResults = MockArgResults();
      archiveDiffer = MockIosArchiveDiffer();
      artifactManager = MockArtifactManager();
      codePushClientWrapper = MockCodePushClientWrapper();
      doctor = MockDoctor();
      engineConfig = MockEngineConfig();
      shorebirdArtifacts = MockShorebirdArtifacts();
      patchDiffChecker = MockPatchDiffChecker();
      platform = MockPlatform();
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
          'ios-release',
          'analyze_snapshot_arm64',
        ),
      )..createSync(recursive: true);
      auth = MockAuth();
      progress = MockProgress();
      logger = MockLogger();
      aotBuildProcessResult = MockProcessResult();
      flutterBuildProcessResult = MockProcessResult();
      flutterPubGetProcessResult = MockProcessResult();
      operatingSystemInterface = MockOperatingSystemInterface();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      flutterValidator = MockShorebirdFlutterValidator();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdValidator = MockShorebirdValidator();

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
      when(() => aotTools.isGeneratePatchDiffBaseSupported())
          .thenAnswer((_) async => false);
      when(
        () => aotTools.generatePatchDiffBase(
          releaseSnapshot: any(named: 'releaseSnapshot'),
          analyzeSnapshotPath: any(named: 'analyzeSnapshotPath'),
        ),
      ).thenAnswer((_) async => File(''));
      when(
        () => aotTools.link(
          base: any(named: 'base'),
          patch: any(named: 'patch'),
          analyzeSnapshot: any(named: 'analyzeSnapshot'),
          workingDirectory: any(named: 'workingDirectory'),
          outputPath: any(named: 'outputPath'),
        ),
      ).thenAnswer((_) async {});
      when(() => argResults['force']).thenReturn(false);
      when(() => argResults['release-version']).thenReturn(version);
      when(() => argResults.rest).thenReturn([]);
      when(() => artifactManager.downloadFile(any())).thenAnswer((_) async {
        final tmpDir = Directory.systemTemp.createTempSync();
        return releaseArtifactFile =
            File(p.join(tmpDir.path, 'release.artifact'))
              ..createSync(recursive: true);
      });
      when(
        () => artifactManager.extractZip(
          zipFile: any(named: 'zipFile'),
          outputDirectory: any(named: 'outputDirectory'),
        ),
      ).thenAnswer((_) async {});
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => doctor.iosCommandValidators).thenReturn([flutterValidator]);
      when(() => engineConfig.localEngine).thenReturn(null);
      when(flutterValidator.validate).thenAnswer((_) async => []);
      when(() => logger.level).thenReturn(Level.info);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.confirm(any())).thenReturn(true);
      when(
        () => operatingSystemInterface.which('flutter'),
      ).thenReturn('/path/to/flutter');
      when(() => platform.operatingSystem).thenReturn(Platform.macOS);
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(
        () => shorebirdArtifacts.getArtifactPath(
          artifact: ShorebirdArtifact.analyzeSnapshot,
        ),
      ).thenReturn(analyzeSnapshotFile.path);
      when(
        () => shorebirdFlutter.installRevision(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => shorebirdArtifacts.getArtifactPath(
          artifact: ShorebirdArtifact.genSnapshot,
        ),
      ).thenReturn(genSnapshotFile.path);
      when(() => shorebirdEnv.flutterRevision)
          .thenReturn(preLinkerFlutterRevision);
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
      when(() => shorebirdEnv.isRunningOnCI).thenReturn(false);
      when(
        () => aotBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => flutterBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(() => flutterPubGetProcessResult.exitCode)
          .thenReturn(ExitCode.success.code);
      when(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
      ).thenAnswer((_) async => appMetadata);
      when(
        () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => [preLinkerRelease]);
      when(
        () => codePushClientWrapper.getReleaseArtifact(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async => xcframeworkArtifact);
      when(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          wasForced: any(named: 'wasForced'),
          hasAssetChanges: any(named: 'hasAssetChanges'),
          hasNativeChanges: any(named: 'hasNativeChanges'),
          platform: any(named: 'platform'),
          track: any(named: 'track'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      ).thenAnswer((_) async {});
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
          force: any(named: 'force'),
        ),
      ).thenAnswer(
        (_) async => DiffStatus(
          hasAssetChanges: false,
          hasNativeChanges: false,
        ),
      );

      command = runWithOverrides(
        () => PatchIosFrameworkCommand(archiveDiffer: archiveDiffer),
      )..testArgResults = argResults;
    });

    test('supports alpha alias', () {
      expect(command.aliases, contains('ios-framework-alpha'));
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

    test(
        'exits with usage code when '
        'both --dry-run and --force are specified', () async {
      when(() => argResults['dry-run']).thenReturn(true);
      when(() => argResults['force']).thenReturn(true);
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, equals(ExitCode.usage.code));
    });

    test('prompts for release when release-version is not specified', () async {
      when(() => argResults['release-version']).thenReturn(null);
      when(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).thenReturn(preLinkerRelease);
      try {
        await runWithOverrides(command.run);
      } catch (_) {}
      await untilCalled(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      );
      final display = verify(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: captureAny(named: 'display'),
        ),
      ).captured.single as String Function(Release);
      expect(display(preLinkerRelease), equals(preLinkerRelease.version));
    });

    test('exits early when no releases are found', () async {
      when(() => argResults['release-version']).thenReturn(null);
      when(
        () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      try {
        await runWithOverrides(command.run);
      } catch (_) {}
      verifyNever(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: captureAny(named: 'display'),
        ),
      );
      verify(() => codePushClientWrapper.getReleases(appId: appId)).called(1);
      verify(() => logger.info('No releases found')).called(1);
    });

    test('exits early when specified release does not exist.', () async {
      when(() => argResults['release-version']).thenReturn('0.0.0');
      try {
        await runWithOverrides(command.run);
      } catch (_) {}
      verifyNever(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: captureAny(named: 'display'),
        ),
      );
      verify(() => codePushClientWrapper.getReleases(appId: appId)).called(1);
      verify(
        () => logger.info('''
No release found for version 0.0.0

Available release versions:
${preLinkerRelease.version}'''),
      ).called(1);
    });

    test(
        '''exits with code 70 if release is in draft state for the ios platform''',
        () async {
      when(
        () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
      ).thenAnswer(
        (_) async => [
          Release(
            id: 0,
            appId: appId,
            version: version,
            flutterRevision: preLinkerFlutterRevision,
            displayName: '1.2.3+1',
            platformStatuses: {ReleasePlatform.ios: ReleaseStatus.draft},
            createdAt: DateTime(2023),
            updatedAt: DateTime(2023),
          ),
        ],
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
        () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
      ).thenAnswer(
        (_) async => [
          Release(
            id: 0,
            appId: appId,
            version: version,
            flutterRevision: preLinkerFlutterRevision,
            displayName: '1.2.3+1',
            platformStatuses: {ReleasePlatform.android: ReleaseStatus.draft},
            createdAt: DateTime(2023),
            updatedAt: DateTime(2023),
          ),
        ],
      );
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
    });

    test(
        '''uses release flutter revision if different than default flutter revision''',
        () async {
      const otherRevision = 'other-revision';
      when(() => shorebirdEnv.flutterRevision).thenReturn(otherRevision);
      when(
        () => aotTools.link(
          base: any(named: 'base'),
          patch: any(named: 'patch'),
          analyzeSnapshot: any(named: 'analyzeSnapshot'),
          workingDirectory: any(named: 'workingDirectory'),
          outputPath: any(named: 'outputPath'),
        ),
      ).thenAnswer((_) async {
        expect(shorebirdEnv.flutterRevision, equals(preLinkerFlutterRevision));
      });
      when(
        () => shorebirdProcess.run(
          'flutter',
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async {
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
        expect(shorebirdEnv.flutterRevision, equals(preLinkerFlutterRevision));
        return aotBuildProcessResult;
      });

      setUpProjectRoot();
      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => shorebirdFlutter.installRevision(
          revision: preLinkerFlutterRevision,
        ),
      ).called(1);
    });

    test(
        'builds using correct flutter revision '
        'when release flutter revision differs', () async {
      when(
        () => platform.script,
      ).thenReturn(
        Uri.file(p.join('bin', 'cache', 'shorebird.snapshot')),
      );
      const otherRevision = 'other-revision';
      when(() => shorebirdEnv.flutterRevision).thenReturn(otherRevision);
      final processWrapper = MockProcessWrapper();
      when(
        () => processWrapper.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async => flutterBuildProcessResult);
      final flutterFile = File(
        p.join(
          '.',
          'bin',
          'cache',
          'flutter',
          preLinkerRelease.flutterRevision,
          'bin',
          'flutter',
        ),
      );
      when(() => shorebirdEnv.flutterBinaryFile).thenReturn(flutterFile);

      setUpProjectRoot();
      setUpProjectRootArtifacts();

      await runWithOverrides(
        () => runScoped(
          () => command.run(),
          values: {
            processRef.overrideWith(
              () => ShorebirdProcess(processWrapper: processWrapper),
            ),
          },
        ),
      );

      verify(
        () => shorebirdFlutter.installRevision(
          revision: preLinkerFlutterRevision,
        ),
      ).called(1);
      verify(
        () => processWrapper.run(
          flutterFile.path,
          any(),
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
        ),
      ).called(1);
    });

    test('aborts when user opts out', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
      verify(() => logger.info('Aborting.')).called(1);
    });

    test('exits with code 70 when build fails', () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oh no');

      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.software.code);
      verify(() => progress.fail('Failed to build: oh no')).called(1);
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
      when(() => argResults['force']).thenReturn(false);
      when(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifact: any(named: 'releaseArtifact'),
          archiveDiffer: archiveDiffer,
          force: any(named: 'force'),
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
          force: false,
        ),
      ).called(1);
      verifyNever(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          wasForced: any(named: 'wasForced'),
          hasAssetChanges: any(named: 'hasAssetChanges'),
          hasNativeChanges: any(named: 'hasNativeChanges'),
          platform: any(named: 'platform'),
          track: any(named: 'track'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      );
    });

    test(
        '''exits with code 70 if zipAndConfirmUnpatchableDiffsIfNecessary throws UnpatchableChangeException''',
        () async {
      when(() => argResults['force']).thenReturn(false);
      when(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifact: any(named: 'releaseArtifact'),
          archiveDiffer: archiveDiffer,
          force: any(named: 'force'),
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
          force: false,
        ),
      ).called(1);
      verifyNever(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          wasForced: any(named: 'wasForced'),
          hasAssetChanges: any(named: 'hasAssetChanges'),
          hasNativeChanges: any(named: 'hasNativeChanges'),
          platform: any(named: 'platform'),
          track: any(named: 'track'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      );
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
          wasForced: any(named: 'wasForced'),
          hasAssetChanges: any(named: 'hasAssetChanges'),
          hasNativeChanges: any(named: 'hasNativeChanges'),
        ),
      );
      verify(() => logger.info('No issues detected.')).called(1);
    });

    test('does not prompt on --force', () async {
      when(() => argResults['force']).thenReturn(true);
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(() => logger.confirm(any()));
      verify(
        () => codePushClientWrapper.publishPatch(
          appId: appId,
          releaseId: preLinkerRelease.id,
          wasForced: true,
          hasAssetChanges: false,
          hasNativeChanges: false,
          platform: ReleasePlatform.ios,
          track: track,
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      ).called(1);
    });

    test('reports when patch has asset and native changes', () async {
      when(() => argResults['force']).thenReturn(true);
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
          force: any(named: 'force'),
        ),
      ).thenAnswer(
        (_) async => DiffStatus(
          hasAssetChanges: true,
          hasNativeChanges: true,
        ),
      );

      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(() => logger.confirm(any()));
      verify(
        () => codePushClientWrapper.publishPatch(
          appId: appId,
          releaseId: postLinkerRelease.id,
          wasForced: true,
          hasAssetChanges: true,
          hasNativeChanges: true,
          platform: ReleasePlatform.ios,
          track: track,
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      ).called(1);
    });

    test('succeeds when patch is successful', () async {
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      verify(
        () => logger.info(
          any(
            that: contains(
              '''
🕹️  Platform: ${lightCyan.wrap('ios')} ${lightCyan.wrap('[aarch64 (0 B)]')}
🟢 Track: ${lightCyan.wrap('Production')}''',
            ),
          ),
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.publishPatch(
          appId: appId,
          releaseId: preLinkerRelease.id,
          wasForced: false,
          hasAssetChanges: false,
          hasNativeChanges: false,
          platform: ReleasePlatform.ios,
          track: track,
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
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

    test('does not prompt if running on CI', () async {
      when(() => shorebirdEnv.isRunningOnCI).thenReturn(true);
      setUpProjectRoot();
      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(() => logger.confirm(any()));
    });

    group('when the engine revision supports the linker', () {
      setUp(() {
        setUpProjectRoot();
        setUpProjectRootArtifacts();

        when(
          () => codePushClientWrapper.getReleases(
            appId: any(named: 'appId'),
          ),
        ).thenAnswer((_) async => [postLinkerRelease]);
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
              workingDirectory: any(named: 'workingDirectory'),
              outputPath: any(named: 'outputPath'),
            ),
          ).called(1);
        });
      });

      test('attempts to link the AOT file', () async {
        await runWithOverrides(command.run);
        verify(
          () => aotTools.link(
            base: any(named: 'base'),
            patch: any(named: 'patch'),
            analyzeSnapshot: any(named: 'analyzeSnapshot'),
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
    });

    group('when aot-tools supports generating patch diff base', () {
      const diffPath = 'path/to/diff';
      setUp(() {
        setUpProjectRoot();
        setUpProjectRootArtifacts();

        when(() => aotTools.isGeneratePatchDiffBaseSupported())
            .thenAnswer((_) async => true);
        when(
          () => artifactManager.createDiff(
            releaseArtifactPath: any(named: 'releaseArtifactPath'),
            patchArtifactPath: any(named: 'patchArtifactPath'),
          ),
        ).thenAnswer((_) async => diffPath);
      });

      group('when release artifact fails to download', () {
        setUp(() {
          when(() => artifactManager.downloadFile(any()))
              .thenAnswer((_) async => File(''));
        });

        test('prints error and exits with code 70', () async {
          final exitCode = await runWithOverrides(command.run);

          expect(exitCode, equals(ExitCode.software.code));
          verify(
            () =>
                progress.fail('Exception: Failed to download release artifact'),
          ).called(1);
        });
      });

      group('when generatePatchDiffBase errors', () {
        const errorMessage = 'oops something went wrong';
        setUp(() {
          when(
            () => aotTools.generatePatchDiffBase(
              releaseSnapshot: any(named: 'releaseSnapshot'),
              analyzeSnapshotPath: any(named: 'analyzeSnapshotPath'),
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
        await runWithOverrides(command.run);
        verify(
          () => codePushClientWrapper.publishPatch(
            appId: appId,
            releaseId: preLinkerRelease.id,
            wasForced: false,
            hasAssetChanges: false,
            hasNativeChanges: false,
            platform: ReleasePlatform.ios,
            track: track,
            patchArtifactBundles: any(
              named: 'patchArtifactBundles',
              that: isA<Map<Arch, PatchArtifactBundle>>()
                  .having((e) => e[Arch.arm64]!.path, 'patch path', diffPath),
            ),
          ),
        ).called(1);
      });
    });
  });
}

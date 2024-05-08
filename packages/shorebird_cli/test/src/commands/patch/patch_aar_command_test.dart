import 'dart:io' hide Platform;

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/cache.dart' show Cache, cacheRef;
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../mocks.dart';

void main() {
  group(PatchAarCommand, () {
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const flutterVersionAndRevision = '3.10.6 (83305b5088)';
    const appId = 'test-app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const buildNumber = '1.0';
    const versionName = '1.2.3';
    const versionCode = '1';
    const version = '$versionName+$versionCode';
    const operatingSystem = 'macOS';
    const operatingSystemVersion = '11.0.0';
    const arch = 'aarch64';
    const releasePlatform = ReleasePlatform.android;
    const track = DeploymentTrack.production;
    const appDisplayName = 'Test App';
    final appMetadata = AppMetadata(
      appId: appId,
      displayName: appDisplayName,
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );
    const androidPackageName = 'com.example.my_flutter_module';
    const releaseArtifact = ReleaseArtifact(
      id: 0,
      releaseId: 0,
      arch: arch,
      platform: releasePlatform,
      hash: '#',
      size: 42,
      url: 'https://example.com/release.so',
    );
    const aarArtifact = ReleaseArtifact(
      id: 0,
      releaseId: 0,
      arch: arch,
      platform: releasePlatform,
      hash: '#',
      size: 42,
      url: 'https://example.com/release.aar',
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
    final releaseArtifactFile = File('release.artifact');

    late AndroidArchiveDiffer archiveDiffer;
    late ArgResults argResults;
    late ArtifactManager artifactManager;
    late Auth auth;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory shorebirdRoot;
    late Directory projectRoot;
    late Directory flutterDirectory;
    late OperatingSystemInterface operatingSystemInterface;
    late PatchDiffChecker patchDiffChecker;
    late Platform platform;
    late Progress progress;
    late ShorebirdLogger logger;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterPubGetProcessResult;
    late http.Client httpClient;
    late Cache cache;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdValidator shorebirdValidator;
    late PatchAarCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactManagerRef.overrideWith(() => artifactManager),
          authRef.overrideWith(() => auth),
          cacheRef.overrideWith(() => cache),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          httpClientRef.overrideWith(() => httpClient),
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

    setUpAll(() {
      registerFallbackValue(CreatePatchMetadata.forTest());
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(FileSetDiff.empty());
      registerFallbackValue(MockHttpClient());
      registerFallbackValue(Uri.parse('https://example.com'));
      registerFallbackValue(FakeBaseRequest());
      registerFallbackValue(FakeShorebirdProcess());
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(DeploymentTrack.production);
    });

    setUp(() {
      archiveDiffer = MockAndroidArchiveDiffer();
      argResults = MockArgResults();
      artifactManager = MockArtifactManager();
      auth = MockAuth();
      codePushClientWrapper = MockCodePushClientWrapper();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      projectRoot = Directory.systemTemp.createTempSync();
      flutterDirectory = Directory(
        p.join(shorebirdRoot.path, 'bin', 'cache', 'flutter'),
      );
      operatingSystemInterface = MockOperatingSystemInterface();
      patchDiffChecker = MockPatchDiffChecker();
      platform = MockPlatform();
      progress = MockProgress();
      logger = MockShorebirdLogger();
      flutterBuildProcessResult = MockProcessResult();
      flutterPubGetProcessResult = MockProcessResult();
      httpClient = MockHttpClient();
      cache = MockCache();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdValidator = MockShorebirdValidator();

      when(() => operatingSystemInterface.which('flutter'))
          .thenReturn('/path/to/flutter');
      when(() => platform.environment).thenReturn({});
      when(() => platform.operatingSystem).thenReturn(operatingSystem);
      when(() => platform.operatingSystemVersion)
          .thenReturn(operatingSystemVersion);
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
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
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(
        () => shorebirdEnv.androidPackageName,
      ).thenReturn(androidPackageName);
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
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
        () => artifactManager.createDiff(
          patchArtifactPath: any(named: 'patchArtifactPath'),
          releaseArtifactPath: any(named: 'releaseArtifactPath'),
        ),
      ).thenAnswer((_) async {
        final tempDir = await Directory.systemTemp.createTemp();
        final diffPath = p.join(tempDir.path, 'diff.patch');
        File(diffPath)
          ..createSync(recursive: true)
          ..writeAsStringSync('diff');
        return diffPath;
      });
      when(() => artifactManager.downloadFile(any()))
          .thenAnswer((_) async => releaseArtifactFile);
      when(
        () => archiveDiffer.changedFiles(any(), any()),
      ).thenAnswer((_) async => FileSetDiff.empty());
      when(
        () => archiveDiffer.containsPotentiallyBreakingAssetDiffs(any()),
      ).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['dry-run']).thenReturn(false);
      when(() => argResults['build-number']).thenReturn(buildNumber);
      when(() => argResults['release-version']).thenReturn(version);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(() => logger.level).thenReturn(Level.info);
      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(version);
      when(() => logger.confirm(any())).thenReturn(true);
      when(
        () => flutterBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => flutterPubGetProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
      );
      when(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
      ).thenAnswer((_) async => appMetadata);
      when(
        () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => [release]);
      when(
        () => codePushClientWrapper.getReleaseArtifacts(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          architectures: any(named: 'architectures'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer(
        (_) async => {
          Arch.arm32: releaseArtifact,
          Arch.arm64: releaseArtifact,
          Arch.x86_64: releaseArtifact,
        },
      );
      when(
        () => codePushClientWrapper.getReleaseArtifact(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          arch: 'aar',
          platform: ReleasePlatform.android,
        ),
      ).thenAnswer((_) async => aarArtifact);
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
      when(() => cache.updateAll()).thenAnswer((_) async => {});
      when(
        () => cache.getArtifactDirectory(any()),
      ).thenReturn(Directory.systemTemp.createTempSync());
      when(
        () => shorebirdFlutter.getVersionAndRevision(),
      ).thenAnswer((_) async => flutterVersionAndRevision);
      when(
        () => shorebirdFlutter.installRevision(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
          localArtifact: any(named: 'localArtifact'),
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

      command = runWithOverrides(
        () => PatchAarCommand(
          archiveDiffer: archiveDiffer,
          unzipFn: (_, __) async {},
        ),
      )..testArgResults = argResults;
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
        ),
      ).called(1);
    });

    test('exits with 78 if no module entry exists in pubspec.yaml', () async {
      when(() => shorebirdEnv.androidPackageName).thenReturn(null);
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.config.code);
    });

    test('prompts for release when release-version is not specified', () async {
      when(() => argResults['release-version']).thenReturn(null);
      when(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).thenReturn(release);
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
      expect(display(release), equals(release.version));
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
${release.version}'''),
      ).called(1);
    });

    test(
        '''exits with code 70 if release is in draft state for the android platform''',
        () async {
      when(
        () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
      ).thenAnswer(
        (_) async => [
          Release(
            id: 0,
            appId: appId,
            version: version,
            flutterRevision: flutterRevision,
            displayName: '1.2.3+1',
            platformStatuses: {ReleasePlatform.android: ReleaseStatus.draft},
            createdAt: DateTime(2023),
            updatedAt: DateTime(2023),
          ),
        ],
      );
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.software.code);
      verify(
        () => logger.err('''
Release 1.2.3+1 is in an incomplete state. It's possible that the original release was terminated or failed to complete.
Please re-run the release command for this version or create a new release.'''),
      ).called(1);
    });

    test('proceeds if release is in draft state for non-android platform',
        () async {
      when(
        () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
      ).thenAnswer(
        (_) async => [
          Release(
            id: 0,
            appId: appId,
            version: version,
            flutterRevision: flutterRevision,
            displayName: '1.2.3+1',
            platformStatuses: {ReleasePlatform.ios: ReleaseStatus.draft},
            createdAt: DateTime(2023),
            updatedAt: DateTime(2023),
          ),
        ],
      );
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
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
        setUpProjectRootArtifacts();

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.software.code));
        verify(
          () => shorebirdFlutter.installRevision(
            revision: release.flutterRevision,
          ),
        ).called(1);
      });
    });

    test('exits with code 70 when downloading release artifact fails',
        () async {
      final exception = Exception('oops');
      when(
        () => artifactManager.downloadFile(
          any(),
          outputPath: any(named: 'outputPath'),
        ),
      ).thenThrow(exception);
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      verify(() => progress.fail('$exception')).called(1);
      expect(exitCode, ExitCode.software.code);
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
          release.flutterRevision,
          'bin',
          'flutter',
        ),
      );
      when(() => shorebirdEnv.flutterBinaryFile).thenReturn(flutterFile);
      when(
        () => shorebirdProcess.run(
          'flutter',
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async {
        // Ensure we're building with the correct flutter revision.
        expect(shorebirdEnv.flutterRevision, equals(release.flutterRevision));
        return flutterBuildProcessResult;
      });
      setUpProjectRootArtifacts();

      await runWithOverrides(
        () => runScoped(
          () => command.run(),
          values: {
            shorebirdEnvRef.overrideWith(() => shorebirdEnv),
            processRef.overrideWith(
              () => ShorebirdProcess(processWrapper: processWrapper),
            ),
          },
        ),
      );

      verify(
        () => shorebirdFlutter.installRevision(
          revision: release.flutterRevision,
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

    test('exits with code 70 when building fails', () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oops');
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, equals(ExitCode.software.code));
    });

    test(
        '''exits with code 0 if confirmUnpatchableDiffsIfNecessary throws UserCancelledException''',
        () async {
      when(
        () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
          localArtifact: any(named: 'localArtifact'),
          releaseArtifact: any(named: 'releaseArtifact'),
          archiveDiffer: archiveDiffer,
          allowAssetChanges: any(named: 'allowAssetChanges'),
          allowNativeChanges: any(named: 'allowNativeChanges'),
        ),
      ).thenThrow(UserCancelledException());
      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
          localArtifact: any(named: 'localArtifact'),
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

    test(
        '''exits with code 70 if confirmUnpatchableDiffsIfNecessary throws UnpatchableChangeException''',
        () async {
      when(
        () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
          localArtifact: any(named: 'localArtifact'),
          releaseArtifact: any(named: 'releaseArtifact'),
          archiveDiffer: archiveDiffer,
          allowAssetChanges: any(named: 'allowAssetChanges'),
          allowNativeChanges: any(named: 'allowNativeChanges'),
        ),
      ).thenThrow(UnpatchableChangeException());

      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
          localArtifact: any(named: 'localArtifact'),
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

    test('exits with code 70 and prints error when creating diff fails',
        () async {
      final error = Exception('oops something went wrong');
      when(
        () => artifactManager.createDiff(
          releaseArtifactPath: any(named: 'releaseArtifactPath'),
          patchArtifactPath: any(named: 'patchArtifactPath'),
        ),
      ).thenThrow(error);
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      verify(() => progress.fail('$error')).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('does not create patch on --dry-run', () async {
      when(() => argResults['dry-run']).thenReturn(true);
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, equals(ExitCode.success.code));
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
      verify(() => logger.info('No issues detected.')).called(1);
    });

    test('aborts when user opts out', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
      verify(() => logger.info('Aborting.')).called(1);
    });

    test(
        '''forwards allow-asset-diffs and allow-native-diffs to patch diff checker''',
        () async {
      setUpProjectRootArtifacts();

      when(() => argResults['allow-asset-diffs']).thenReturn(true);
      when(() => argResults['allow-native-diffs']).thenReturn(true);

      await runWithOverrides(command.run);

      verify(
        () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
          localArtifact: any(named: 'localArtifact'),
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
        () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
          localArtifact: any(named: 'localArtifact'),
          releaseArtifact: any(named: 'releaseArtifact'),
          archiveDiffer: archiveDiffer,
          allowAssetChanges: false,
          allowNativeChanges: false,
        ),
      ).called(1);
    });

    test('reports when patch has asset and native changes', () async {
      when(() => archiveDiffer.containsPotentiallyBreakingAssetDiffs(any()))
          .thenReturn(true);
      when(() => archiveDiffer.containsPotentiallyBreakingNativeDiffs(any()))
          .thenReturn(true);
      when(() => archiveDiffer.changedFiles(any(), any()))
          .thenAnswer((_) async => FileSetDiff.empty());
      when(
        () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
          localArtifact: any(named: 'localArtifact'),
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

      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => codePushClientWrapper.publishPatch(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          track: track,
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
          metadata: any(
            named: 'metadata',
            that: isA<CreatePatchMetadata>()
                .having(
                  (m) => m.releasePlatform,
                  'releasePlatform',
                  ReleasePlatform.android,
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

    test('succeeds when patch is successful', () async {
      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.success.code);
      verify(
        () => logger.info(
          any(
            that: contains(
              '''
🕹️  Platform: ${lightCyan.wrap(releasePlatform.name)} ${lightCyan.wrap('[arm32 (4 B), arm64 (4 B), x86_64 (4 B)]')}
🟢 Track: ${lightCyan.wrap('Production')}''',
            ),
          ),
        ),
      ).called(1);

      verify(() => codePushClientWrapper.getApp(appId: appId)).called(1);
      verify(() => codePushClientWrapper.getReleases(appId: appId)).called(1);
      verify(
        () => codePushClientWrapper.getReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          architectures: Arch.values,
          platform: releasePlatform,
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.getReleaseArtifact(
          appId: appId,
          releaseId: release.id,
          arch: 'aar',
          platform: releasePlatform,
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.publishPatch(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          track: track,
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
          metadata: const CreatePatchMetadata(
            releasePlatform: releasePlatform,
            usedIgnoreAssetChangesFlag: false,
            hasAssetChanges: false,
            usedIgnoreNativeChangesFlag: false,
            hasNativeChanges: false,
            linkPercentage: null,
            environment: BuildEnvironmentMetadata(
              shorebirdVersion: packageVersion,
              operatingSystem: operatingSystem,
              operatingSystemVersion: operatingSystemVersion,
              xcodeVersion: null,
            ),
          ),
        ),
      ).called(1);
    });

    test('runs flutter pub get with system flutter after successful build',
        () async {
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

    test('does not prompt if unable to accept user input', () async {
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);
      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(() => logger.confirm(any()));
    });
  });
}

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
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
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
  group(PatchAndroidCommand, () {
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const appId = 'test-app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
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
    const releaseArtifact = ReleaseArtifact(
      id: 0,
      releaseId: 0,
      arch: arch,
      platform: releasePlatform,
      hash: '#',
      size: 42,
      url: 'https://example.com',
    );
    const aabArtifact = ReleaseArtifact(
      id: 0,
      releaseId: 0,
      arch: arch,
      platform: releasePlatform,
      hash: '#',
      size: 42,
      url: 'https://example.com/release.aab',
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
    const pubspecYamlContent = '''
name: example
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  assets:
    - shorebird.yaml''';

    late AndroidArchiveDiffer archiveDiffer;
    late ArgResults argResults;
    late ArtifactManager artifactManager;
    late Auth auth;
    late Bundletool bundletool;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory flutterDirectory;
    late Directory shorebirdRoot;
    late Directory projectRoot;
    late Doctor doctor;
    late Java java;
    late OperatingSystemInterface operatingSystemInterface;
    late PatchDiffChecker patchDiffChecker;
    late Platform platform;
    late Progress progress;
    late Logger logger;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterPubGetProcessResult;
    late http.Client httpClient;
    late Cache cache;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdValidator shorebirdValidator;
    late PatchAndroidCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          artifactManagerRef.overrideWith(() => artifactManager),
          authRef.overrideWith(() => auth),
          bundletoolRef.overrideWith(() => bundletool),
          cacheRef.overrideWith(() => cache),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          httpClientRef.overrideWith(() => httpClient),
          javaRef.overrideWith(() => java),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          patchDiffCheckerRef.overrideWith(() => patchDiffChecker),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
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
    }

    void setUpProjectRootArtifacts({String? flavor}) {
      for (final archMetadata
          in ShorebirdBuildMixin.allAndroidArchitectures.values) {
        final artifactPath = p.join(
          projectRoot.path,
          'build',
          'app',
          'intermediates',
          'stripped_native_libs',
          flavor != null ? '${flavor}Release' : 'release',
          'out',
          'lib',
          archMetadata.path,
          'libapp.so',
        );
        File(artifactPath).createSync(recursive: true);
      }
    }

    setUpAll(() {
      registerFallbackValue(CreatePatchMetadata.forTest());
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(FileSetDiff.empty());
      registerFallbackValue(MockHttpClient());
      registerFallbackValue(Uri.parse('https://example.com'));
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(FakeBaseRequest());
      registerFallbackValue(FakeShorebirdProcess());
      registerFallbackValue(DeploymentTrack.production);
    });

    setUp(() {
      archiveDiffer = MockAndroidArchiveDiffer();
      argResults = MockArgResults();
      artifactManager = MockArtifactManager();
      auth = MockAuth();
      bundletool = MockBundleTool();
      codePushClientWrapper = MockCodePushClientWrapper();
      doctor = MockDoctor();
      java = MockJava();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      projectRoot = Directory.systemTemp.createTempSync();
      flutterDirectory = Directory(
        p.join(shorebirdRoot.path, 'bin', 'cache', 'flutter'),
      );
      patchDiffChecker = MockPatchDiffChecker();
      platform = MockPlatform();
      progress = MockProgress();
      logger = MockLogger();
      flutterBuildProcessResult = MockProcessResult();
      flutterPubGetProcessResult = MockProcessResult();
      httpClient = MockHttpClient();
      flutterValidator = MockShorebirdFlutterValidator();
      cache = MockCache();
      operatingSystemInterface = MockOperatingSystemInterface();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();
      command = runWithOverrides(
        () => PatchAndroidCommand(archiveDiffer: archiveDiffer),
      )..testArgResults = argResults;

      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
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
      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(
        () => shorebirdFlutter.installRevision(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => shorebirdProcess.run(
          'flutter',
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => flutterBuildProcessResult);
      when(
        () => shorebirdProcess.run(
          'flutter',
          ['--no-version-check', 'pub', 'get', '--offline'],
          runInShell: any(named: 'runInShell'),
          useVendedFlutter: false,
        ),
      ).thenAnswer((_) async => flutterPubGetProcessResult);
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
        () => archiveDiffer.assetsFileSetDiff(any()),
      ).thenReturn(FileSetDiff.empty());
      when(
        () => archiveDiffer.nativeFileSetDiff(any()),
      ).thenReturn(FileSetDiff.empty());
      when(
        () => archiveDiffer.containsPotentiallyBreakingAssetDiffs(any()),
      ).thenReturn(false);
      when(
        () => archiveDiffer.containsPotentiallyBreakingNativeDiffs(any()),
      ).thenReturn(false);
      when(() => argResults['arch']).thenReturn(arch);
      when(() => argResults['staging']).thenReturn(false);
      when(() => argResults['dry-run']).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults.wasParsed(any())).thenReturn(true);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(version);
      when(() => logger.confirm(any())).thenReturn(true);
      when(
        () => flutterBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(() => flutterPubGetProcessResult.exitCode).thenReturn(
        ExitCode.success.code,
      );
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
      );

      when(
        () => codePushClientWrapper.getApp(
          appId: any(named: 'appId'),
        ),
      ).thenAnswer((_) async => appMetadata);
      when(
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
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
          arch: 'aab',
          platform: ReleasePlatform.android,
        ),
      ).thenAnswer((_) async => aabArtifact);
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
      when(
        () => doctor.androidCommandValidators,
      ).thenReturn([flutterValidator]);
      when(flutterValidator.validate).thenAnswer((_) async => []);
      when(() => cache.updateAll()).thenAnswer((_) async => {});
      when(() => bundletool.getVersionName(any())).thenAnswer(
        (_) async => versionName,
      );
      when(() => bundletool.getVersionCode(any())).thenAnswer(
        (_) async => versionCode,
      );
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
        ),
      ).thenAnswer((_) async {});
      when(() => operatingSystemInterface.which('flutter'))
          .thenReturn('/path/to/flutter');
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
      when(() => platform.operatingSystem).thenReturn(operatingSystem);
      when(() => platform.operatingSystemVersion)
          .thenReturn(operatingSystemVersion);
      when(() => shorebirdEnv.isRunningOnCI).thenReturn(false);
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

    test('exits with code 70 when building fails', () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oops');

      setUpProjectRoot();
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
    });

    test('exits with code 70 when build artifacts cannot be found', () async {
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(() => logger.err('Cannot find patch build artifacts.')).called(1);
      verify(
        () => logger.info(
          any(
            that: contains('Please run `shorebird cache clean` and try again'),
          ),
        ),
      ).called(1);
    });

    test(
        '''exits with code 70 if release is in draft state for the android platform''',
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
          flutterRevision: flutterRevision,
          displayName: '1.2.3+1',
          platformStatuses: {releasePlatform: ReleaseStatus.draft},
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

    test('proceeds if release is in draft state for non-android platform',
        () async {
      when(
        () => codePushClientWrapper.getReleases(
          appId: any(named: 'appId'),
        ),
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
      setUpProjectRoot();
      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.success.code);
      verify(
        () => logger.info(
          any(
            that: stringContainsInOrder([
              '''The release you are trying to patch was built with a different version of Flutter.''',
              'Release Flutter Revision: ${release.flutterRevision}',
              'Current Flutter Revision: $otherRevision',
            ]),
          ),
        ),
      ).called(1);
    });

    group('when release-version option is provided', () {
      setUp(() {
        when(() => argResults['release-version']).thenReturn(release.version);
      });

      test('does not extract release version from app bundle', () async {
        setUpProjectRoot();
        setUpProjectRootArtifacts();
        await runWithOverrides(command.run);
        verifyNever(() => bundletool.getVersionName(any()));
        verifyNever(() => bundletool.getVersionCode(any()));
        verifyNever(() => logger.progress('Detecting release version'));
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

        setUpProjectRoot();
        setUpProjectRootArtifacts();
        final exitCode = await runWithOverrides(command.run);
        expect(exitCode, ExitCode.success.code);
        verify(
          () => shorebirdEnv.copyWith(flutterRevisionOverride: flutterRevision),
        ).called(1);

        verify(
          () => shorebirdProcess.run(
            'flutter',
            [
              'build',
              'appbundle',
              '--release',
            ],
            runInShell: any(named: 'runInShell'),
          ),
        ).called(1);
      });
    });

    group('when release-version option is not provided', () {
      test('extracts release version from app bundle', () async {
        setUpProjectRoot();
        setUpProjectRootArtifacts();
        await runWithOverrides(command.run);
        verify(() => bundletool.getVersionName(any())).called(1);
        verify(() => bundletool.getVersionCode(any())).called(1);
        verify(() => logger.progress('Detecting release version')).called(1);
      });
    });

    test('errors when detecting release version name fails', () async {
      final exception = Exception(
        'Failed to extract version name from app bundle: oops',
      );
      when(() => bundletool.getVersionName(any())).thenThrow(exception);
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.software.code);
      verify(() => progress.fail('$exception')).called(1);
    });

    test('errors when detecting release version code fails', () async {
      final exception = Exception(
        'Failed to extract version code from app bundle: oops',
      );
      when(() => bundletool.getVersionCode(any())).thenThrow(exception);
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.software.code);
      verify(() => progress.fail('$exception')).called(1);
    });

    test('prints release version when detected', () async {
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => progress.complete('Detected release version 1.2.3+1'),
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

    test('exits with code 70 when downloading release artifact fails',
        () async {
      final exception = Exception('oops');
      when(
        () => artifactManager.downloadFile(
          any(),
          outputPath: any(named: 'outputPath'),
        ),
      ).thenThrow(exception);
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      verify(() => progress.fail('$exception')).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('errors when detecting release version name fails', () async {
      final exception = Exception(
        'Failed to extract version name from app bundle: oops',
      );
      when(() => bundletool.getVersionName(any())).thenThrow(exception);
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.software.code);
      verify(() => progress.fail('$exception')).called(1);
    });

    test('errors when detecting release version code fails', () async {
      final exception = Exception(
        'Failed to extract version code from app bundle: oops',
      );
      when(() => bundletool.getVersionCode(any())).thenThrow(exception);
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.software.code);
      verify(() => progress.fail('$exception')).called(1);
    });

    test('prints release version when detected', () async {
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => progress.complete('Detected release version 1.2.3+1'),
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
        setUpProjectRoot();
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
      setUpProjectRoot();
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

      setUpProjectRoot();
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
      setUpProjectRoot();
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      verify(() => progress.fail('$error')).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('does not create patch on --dry-run', () async {
      when(() => argResults['dry-run']).thenReturn(true);
      setUpProjectRoot();
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

    test(
        '''forwards allow-asset-diffs and allow-native-diffs to patch diff checker''',
        () async {
      setUpProjectRoot();
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

    test('succeeds when patch is successful (production)', () async {
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
      setUpProjectRoot();
      setUpProjectRootArtifacts();

      final exitCode = await runWithOverrides(command.run);

      verify(
        () => shorebirdFlutter.installRevision(
          revision: release.flutterRevision,
        ),
      ).called(1);
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
🕹️  Platform: ${lightCyan.wrap(releasePlatform.name)} ${lightCyan.wrap('[arm32 (4 B), arm64 (4 B), x86_64 (4 B)]')}
🟠 Track: ${lightCyan.wrap('Staging')}''',
            ),
          ),
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.publishPatch(
          appId: appId,
          releaseId: release.id,
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

    test('succeeds when patch is successful with flavors and target', () async {
      const flavor = 'development';
      const target = './lib/main_development.dart';
      when(() => argResults['flavor']).thenReturn(flavor);
      when(() => argResults['target']).thenReturn(target);
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
      setUpProjectRoot();
      File(
        p.join(projectRoot.path, 'shorebird.yaml'),
      ).writeAsStringSync('''
app_id: productionAppId
flavors:
  development: $appId''');
      setUpProjectRootArtifacts(flavor: flavor);
      final exitCode = await runWithOverrides(command.run);
      verify(
        () => codePushClientWrapper.publishPatch(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          track: track,
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
          metadata: any(named: 'metadata'),
        ),
      ).called(1);
      expect(exitCode, ExitCode.success.code);
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

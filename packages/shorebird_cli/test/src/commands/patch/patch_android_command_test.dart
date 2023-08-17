import 'dart:io' hide Platform;

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/bundletool.dart';
import 'package:shorebird_cli/src/cache.dart' show Cache, cacheRef;
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patch_android_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/java.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

class _MockAndroidArchiveDiffer extends Mock implements AndroidArchiveDiffer {}

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockBundleTool extends Mock implements Bundletool {}

class _MockCache extends Mock implements Cache {}

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockDoctor extends Mock implements Doctor {}

class _MockJava extends Mock implements Java {}

class _MockLogger extends Mock implements Logger {}

class _MockPatchDiffChecker extends Mock implements PatchDiffChecker {}

class _MockPlatform extends Mock implements Platform {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockShorebirdFlutter extends Mock implements ShorebirdFlutter {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

class _FakeShorebirdProcess extends Fake implements ShorebirdProcess {}

void main() {
  group(PatchAndroidCommand, () {
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const appId = 'test-app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const versionName = '1.2.3';
    const versionCode = '1';
    const version = '$versionName+$versionCode';
    const arch = 'aarch64';
    const releasePlatform = ReleasePlatform.android;
    const channelName = 'stable';
    const appDisplayName = 'Test App';
    const app = AppMetadata(appId: appId, displayName: appDisplayName);
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
    const release = Release(
      id: 0,
      appId: appId,
      version: version,
      flutterRevision: flutterRevision,
      displayName: '1.2.3+1',
      platformStatuses: {},
    );
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
    late Auth auth;
    late Bundletool bundletool;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory flutterDirectory;
    late Directory shorebirdRoot;
    late Doctor doctor;
    late Java java;
    late PatchDiffChecker patchDiffChecker;
    late Platform platform;
    late Progress progress;
    late Logger logger;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult patchProcessResult;
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
          authRef.overrideWith(() => auth),
          bundletoolRef.overrideWith(() => bundletool),
          cacheRef.overrideWith(() => cache),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          javaRef.overrideWith(() => java),
          loggerRef.overrideWith(() => logger),
          patchDiffCheckerRef.overrideWith(() => patchDiffChecker),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    Directory setUpTempDir() {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('app_id: $appId');
      return tempDir;
    }

    void setUpTempArtifacts(Directory dir, {String? flavor}) {
      for (final archMetadata
          in ShorebirdBuildMixin.allAndroidArchitectures.values) {
        final artifactPath = p.join(
          dir.path,
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
      registerFallbackValue(File(''));
      registerFallbackValue(FileSetDiff.empty());
      registerFallbackValue(Uri.parse('https://example.com'));
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(_FakeBaseRequest());
      registerFallbackValue(_FakeShorebirdProcess());
    });

    setUp(() {
      archiveDiffer = _MockAndroidArchiveDiffer();
      argResults = _MockArgResults();
      auth = _MockAuth();
      bundletool = _MockBundleTool();
      codePushClientWrapper = _MockCodePushClientWrapper();
      doctor = _MockDoctor();
      java = _MockJava();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      flutterDirectory = Directory(
        p.join(shorebirdRoot.path, 'bin', 'cache', 'flutter'),
      );
      patchDiffChecker = _MockPatchDiffChecker();
      platform = _MockPlatform();
      progress = _MockProgress();
      logger = _MockLogger();
      flutterBuildProcessResult = _MockProcessResult();
      patchProcessResult = _MockProcessResult();
      httpClient = _MockHttpClient();
      flutterValidator = _MockShorebirdFlutterValidator();
      cache = _MockCache();
      shorebirdEnv = _MockShorebirdEnv();
      shorebirdProcess = _MockShorebirdProcess();
      shorebirdFlutter = _MockShorebirdFlutter();
      shorebirdValidator = _MockShorebirdValidator();
      command = runWithOverrides(
        () => PatchAndroidCommand(
          archiveDiffer: archiveDiffer,
          httpClient: httpClient,
        ),
      )..testArgResults = argResults;

      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(
        () => shorebirdProcess.run(
          'flutter',
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => flutterBuildProcessResult);
      when(
        () => shorebirdProcess.run(
          any(that: endsWith('patch')),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.positionalArguments[1] as List<String>;
        final diffPath = args[2];
        File(diffPath)
          ..createSync(recursive: true)
          ..writeAsStringSync('diff');
        return patchProcessResult;
      });
      when(() => patchProcessResult.exitCode).thenReturn(ExitCode.success.code);

      when(
        () => archiveDiffer.changedFiles(any(), any()),
      ).thenReturn(FileSetDiff.empty());
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
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['arch']).thenReturn(arch);
      when(() => argResults['channel']).thenReturn(channelName);
      when(() => argResults['dry-run']).thenReturn(false);
      when(() => argResults['force']).thenReturn(false);
      when(() => argResults['release-version']).thenReturn(release.version);
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
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
      );

      when(
        () => codePushClientWrapper.getApp(
          appId: any(named: 'appId'),
        ),
      ).thenAnswer((_) async => app);
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
          channelName: any(named: 'channelName'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => doctor.androidCommandValidators,
      ).thenReturn([flutterValidator]);
      when(flutterValidator.validate).thenAnswer((_) async => []);
      when(() => cache.updateAll()).thenAnswer((_) async => {});
      when(
        () => cache.getArtifactDirectory(any()),
      ).thenReturn(Directory.systemTemp.createTempSync());
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
      when(
        () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
          localArtifact: any(named: 'localArtifact'),
          releaseArtifactUrl: any(named: 'releaseArtifactUrl'),
          archiveDiffer: archiveDiffer,
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async => true);
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

    test(
        'exits with usage code when '
        'both --dry-run and --force are specified', () async {
      when(() => argResults['dry-run']).thenReturn(true);
      when(() => argResults['force']).thenReturn(true);
      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.usage.code));
    });

    test('exits with code 70 when building fails', () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oops');

      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.software.code));
    });

    test(
        '''exits with code 70 if release is in draft state for the android platform''',
        () async {
      when(
        () => codePushClientWrapper.getRelease(
            appId: any(named: 'appId'),
            releaseVersion: any(named: 'releaseVersion')),
      ).thenAnswer(
        (_) async => const Release(
          id: 0,
          appId: appId,
          version: version,
          flutterRevision: flutterRevision,
          displayName: '1.2.3+1',
          platformStatuses: {releasePlatform: ReleaseStatus.draft},
        ),
      );
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
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
        (_) async => const [
          Release(
            id: 0,
            appId: appId,
            version: version,
            flutterRevision: flutterRevision,
            displayName: '1.2.3+1',
            platformStatuses: {ReleasePlatform.ios: ReleaseStatus.draft},
          )
        ],
      );
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.success.code);
    });

    test(
        'errors when shorebird flutter revision '
        'does not match release revision', () async {
      const otherRevision = 'other-revision';
      when(() => shorebirdEnv.flutterRevision).thenReturn(otherRevision);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.software.code);
      verify(
        () => logger.info('''
Either create a new release using:
  ${lightCyan.wrap('shorebird release android')}

Or change your Flutter version and try again using:
  ${lightCyan.wrap('shorebird flutter versions use ${release.flutterRevision}')}'''),
      ).called(1);
    });

    test('errors when detecting release version name fails', () async {
      final exception = Exception(
        'Failed to extract version name from app bundle: oops',
      );
      when(() => bundletool.getVersionName(any())).thenThrow(exception);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.software.code);
      verify(() => progress.fail('$exception')).called(1);
    });

    test('errors when detecting release version code fails', () async {
      final exception = Exception(
        'Failed to extract version code from app bundle: oops',
      );
      when(() => bundletool.getVersionCode(any())).thenThrow(exception);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.software.code);
      verify(() => progress.fail('$exception')).called(1);
    });

    test('prints release version when detected', () async {
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => progress.complete('Detected release version 1.2.3+1'),
      ).called(1);
    });

    test('aborts when user opts out', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.success.code);
      verify(() => logger.info('Aborting.')).called(1);
    });

    test('throws error when release artifact does not exist.', () async {
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          const Stream.empty(),
          HttpStatus.notFound,
          reasonPhrase: 'Not Found',
        ),
      );
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => progress.fail(
          'Exception: Failed to download release artifact: 404 Not Found',
        ),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('errors when detecting release version name fails', () async {
      final exception = Exception(
        'Failed to extract version name from app bundle: oops',
      );
      when(() => bundletool.getVersionName(any())).thenThrow(exception);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.software.code);
      verify(() => progress.fail('$exception')).called(1);
    });

    test('errors when detecting release version code fails', () async {
      final exception = Exception(
        'Failed to extract version code from app bundle: oops',
      );
      when(() => bundletool.getVersionCode(any())).thenThrow(exception);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.software.code);
      verify(() => progress.fail('$exception')).called(1);
    });

    test('prints release version when detected', () async {
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => progress.complete('Detected release version 1.2.3+1'),
      ).called(1);
    });

    test('exits if confirmUnpatchableDiffsIfNecessary returns false', () async {
      when(() => argResults['force']).thenReturn(false);
      when(
        () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
          localArtifact: any(named: 'localArtifact'),
          releaseArtifactUrl: any(named: 'releaseArtifactUrl'),
          archiveDiffer: archiveDiffer,
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async => false);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
          localArtifact: any(named: 'localArtifact'),
          releaseArtifactUrl: Uri.parse(aabArtifact.url),
          archiveDiffer: archiveDiffer,
          force: false,
        ),
      ).called(1);
      verifyNever(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          channelName: any(named: 'channelName'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      );
    });

    test('throws error when creating diff fails', () async {
      const error = 'oops something went wrong';
      when(() => patchProcessResult.exitCode).thenReturn(1);
      when(() => patchProcessResult.stderr).thenReturn(error);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => progress.fail('Exception: Failed to create diff: $error'),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('does not create patch on --dry-run', () async {
      when(() => argResults['dry-run']).thenReturn(true);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          channelName: any(named: 'channelName'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      );
      verify(() => logger.info('No issues detected.')).called(1);
    });

    test('does not prompt on --force', () async {
      when(() => argResults['force']).thenReturn(true);
      when(() => archiveDiffer.containsPotentiallyBreakingAssetDiffs(any()))
          .thenReturn(true);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(() => logger.confirm(any()));
      verify(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          channelName: any(named: 'channelName'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      ).called(1);
    });

    test('succeeds when patch is successful', () async {
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.info(
          any(
            that: contains(
              '''🕹️  Platform: ${lightCyan.wrap(releasePlatform.name)} ${lightCyan.wrap('[arm32 (4 B), arm64 (4 B), x86_64 (4 B)]')}''',
            ),
          ),
        ),
      ).called(1);
      verify(() => logger.success('\n✅ Published Patch!')).called(1);
      expect(exitCode, ExitCode.success.code);
    });

    test(
        'succeeds when patch is successful '
        'with flavors and target', () async {
      const flavor = 'development';
      const target = './lib/main_development.dart';
      when(() => argResults['flavor']).thenReturn(flavor);
      when(() => argResults['target']).thenReturn(target);
      final tempDir = setUpTempDir();
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('''
app_id: productionAppId
flavors:
  development: $appId''');
      setUpTempArtifacts(tempDir, flavor: flavor);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.success('\n✅ Published Patch!')).called(1);
      expect(exitCode, ExitCode.success.code);
    });

    test('does not prompt if running on CI', () async {
      when(() => shorebirdEnv.isRunningOnCI).thenReturn(true);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(() => logger.confirm(any()));
    });
  });
}

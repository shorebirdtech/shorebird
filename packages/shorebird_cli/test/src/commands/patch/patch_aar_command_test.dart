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
import 'package:shorebird_cli/src/cache.dart' show Cache, cacheRef;
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter_manager.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

class _MockAndroidArchiveDiffer extends Mock implements AndroidArchiveDiffer {}

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockCache extends Mock implements Cache {}

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockLogger extends Mock implements Logger {}

class _MockPlatform extends Mock implements Platform {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockProcessWrapper extends Mock implements ProcessWrapper {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

class _MockShorebirdFlutterManager extends Mock
    implements ShorebirdFlutterManager {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

class _FakeShorebirdProcess extends Fake implements ShorebirdProcess {}

void main() {
  group(PatchAarCommand, () {
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const appId = 'test-app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const buildNumber = '1.0';
    const versionName = '1.2.3';
    const versionCode = '1';
    const version = '$versionName+$versionCode';
    const arch = 'aarch64';
    const releasePlatform = ReleasePlatform.android;
    const channelName = 'stable';
    const appDisplayName = 'Test App';
    const appMetadata = AppMetadata(appId: appId, displayName: appDisplayName);
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
    const release = Release(
      id: 0,
      appId: appId,
      version: version,
      flutterRevision: flutterRevision,
      displayName: '1.2.3+1',
      platformStatuses: {},
    );

    late AndroidArchiveDiffer archiveDiffer;
    late ArgResults argResults;
    late Auth auth;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory shorebirdRoot;
    late Directory flutterDirectory;
    late Platform platform;
    late Progress progress;
    late Logger logger;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult patchProcessResult;
    late http.Client httpClient;
    late Cache cache;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutterManager shorebirdFlutterManager;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdValidator shorebirdValidator;
    late PatchAarCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          cacheRef.overrideWith(() => cache),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterManagerRef.overrideWith(
            () => shorebirdFlutterManager,
          ),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    Directory setUpTempDir() => Directory.systemTemp.createTempSync();

    void setUpTempArtifacts(Directory dir) {
      final aarDir = p.join(
        dir.path,
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
      for (final archMetadata
          in ShorebirdBuildMixin.allAndroidArchitectures.values) {
        final artifactPath = p.join(
          aarDir,
          'flutter_release-$buildNumber',
          'jni',
          archMetadata.path,
          'libapp.so',
        );
        File(artifactPath).createSync(recursive: true);
      }
      File(aarPath).createSync(recursive: true);
    }

    setUpAll(() {
      registerFallbackValue(FileSetDiff.empty());
      registerFallbackValue(_FakeBaseRequest());
      registerFallbackValue(_FakeShorebirdProcess());
    });

    setUp(() {
      archiveDiffer = _MockAndroidArchiveDiffer();
      argResults = _MockArgResults();
      auth = _MockAuth();
      codePushClientWrapper = _MockCodePushClientWrapper();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      flutterDirectory = Directory(
        p.join(shorebirdRoot.path, 'bin', 'cache', 'flutter'),
      );
      platform = _MockPlatform();
      progress = _MockProgress();
      logger = _MockLogger();
      flutterBuildProcessResult = _MockProcessResult();
      patchProcessResult = _MockProcessResult();
      httpClient = _MockHttpClient();
      cache = _MockCache();
      shorebirdEnv = _MockShorebirdEnv();
      shorebirdFlutterManager = _MockShorebirdFlutterManager();
      shorebirdProcess = _MockShorebirdProcess();
      shorebirdValidator = _MockShorebirdValidator();

      registerFallbackValue(ReleasePlatform.android);

      when(() => platform.environment).thenReturn({});
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(
        () => shorebirdEnv.androidPackageName,
      ).thenReturn(androidPackageName);
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
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

      when(
        () => archiveDiffer.changedFiles(any(), any()),
      ).thenReturn(FileSetDiff.empty());
      when(
        () => archiveDiffer.containsPotentiallyBreakingAssetDiffs(any()),
      ).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['channel']).thenReturn(channelName);
      when(() => argResults['dry-run']).thenReturn(false);
      when(() => argResults['force']).thenReturn(false);
      when(() => argResults['build-number']).thenReturn(buildNumber);
      when(() => argResults['release-version']).thenReturn(version);
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
      when(() => patchProcessResult.exitCode).thenReturn(ExitCode.success.code);
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
      );
      when(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
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
          arch: 'aar',
          platform: ReleasePlatform.android,
        ),
      ).thenAnswer((_) async => aarArtifact);
      when(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          channelName: any(named: 'channelName'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      ).thenAnswer((_) async {});
      when(() => cache.updateAll()).thenAnswer((_) async => {});
      when(
        () => cache.getArtifactDirectory(any()),
      ).thenReturn(Directory.systemTemp.createTempSync());
      when(
        () => shorebirdFlutterManager.installRevision(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(
        () => PatchAarCommand(
          archiveDiffer: archiveDiffer,
          httpClient: httpClient,
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

    test(
        'exits with usage code when '
        'both --dry-run and --force are specified', () async {
      when(() => argResults['dry-run']).thenReturn(true);
      when(() => argResults['force']).thenReturn(true);
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, equals(ExitCode.usage.code));
    });

    test(
        'installs correct flutter revision '
        'when release flutter revision differs', () async {
      const otherRevision = 'other-revision';
      when(() => shorebirdEnv.flutterRevision).thenReturn(otherRevision);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => logger.progress(
          'Switching to Flutter revision ${release.flutterRevision}',
        ),
      ).called(1);
      verify(
        () => shorebirdFlutterManager.installRevision(
          revision: release.flutterRevision,
        ),
      ).called(1);
    });

    test(
        'builds using correct flutter revision '
        'when release flutter revision differs', () async {
      when(
        () => platform.script,
      ).thenReturn(Uri.parse('file:///bin/cache/shorebird.snapshot'));
      const otherRevision = 'other-revision';
      when(() => shorebirdEnv.flutterRevision).thenReturn(otherRevision);
      final processWrapper = _MockProcessWrapper();
      when(
        () => processWrapper.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async => flutterBuildProcessResult);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      await IOOverrides.runZoned(
        () => runWithOverrides(
          () => runScoped(
            () => command.run(),
            values: {
              processRef.overrideWith(
                () => ShorebirdProcess(
                  logger: logger,
                  processWrapper: processWrapper,
                ),
              ),
            },
          ),
        ),
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => processWrapper.run(
          '/bin/cache/flutter/${release.flutterRevision}/bin/flutter',
          any(),
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
        ),
      ).called(1);
    });

    test(
        'exits with code 70 when '
        'unable to install correct flutter revision', () async {
      final exception = Exception('oops');
      const otherRevision = 'other-revision';
      when(() => shorebirdEnv.flutterRevision).thenReturn(otherRevision);
      when(
        () => shorebirdFlutterManager.installRevision(
          revision: any(named: 'revision'),
        ),
      ).thenThrow(exception);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => logger.progress(
          'Switching to Flutter revision ${release.flutterRevision}',
        ),
      ).called(1);
      verify(
        () => shorebirdFlutterManager.installRevision(
          revision: release.flutterRevision,
        ),
      ).called(1);
      verify(() => progress.fail('$exception')).called(1);
    });

    test('exits with code 70 when building fails', () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oops');
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, equals(ExitCode.software.code));
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
          (_) async => const Release(
            id: 0,
            appId: appId,
            version: version,
            flutterRevision: flutterRevision,
            displayName: '1.2.3+1',
            platformStatuses: {ReleasePlatform.android: ReleaseStatus.draft},
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
      },
    );

    test(
      'proceeds if release is in draft state for non-android platform',
      () async {
        when(
          () => codePushClientWrapper.getRelease(
            appId: any(named: 'appId'),
            releaseVersion: any(named: 'releaseVersion'),
          ),
        ).thenAnswer(
          (_) async => const Release(
            id: 0,
            appId: appId,
            version: version,
            flutterRevision: flutterRevision,
            displayName: '1.2.3+1',
            platformStatuses: {ReleasePlatform.ios: ReleaseStatus.draft},
          ),
        );
        final tempDir = setUpTempDir();
        setUpTempArtifacts(tempDir);
        final exitCode = await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );
        expect(exitCode, ExitCode.success.code);
      },
    );

    test('throws error when release artifact does not exist.', () async {
      when(
        () => httpClient.send(
          any(
            that: isA<http.Request>().having(
              (req) => req.url.toString(),
              'url',
              endsWith('so'),
            ),
          ),
        ),
      ).thenAnswer(
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
        () => progress.fail(any(that: contains('404 Not Found'))),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws error when aar fails to download', () async {
      when(
        () => httpClient.send(
          any(
            that: isA<http.Request>().having(
              (req) => req.url.toString(),
              'url',
              endsWith('aar'),
            ),
          ),
        ),
      ).thenAnswer(
        (_) async => http.StreamedResponse(
          const Stream.empty(),
          HttpStatus.internalServerError,
          reasonPhrase: 'Internal Server Error',
        ),
      );

      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.software.code);
    });

    test('prompts user to continue when asset changes are detected', () async {
      when(() => archiveDiffer.containsPotentiallyBreakingAssetDiffs(any()))
          .thenReturn(true);

      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
      verify(
        () => logger.info(
          any(
            that: contains(
              '''The Android Archive contains asset changes, which will not be included in the patch.''',
            ),
          ),
        ),
      ).called(1);
      verify(() => logger.confirm('Continue anyways?')).called(1);
    });

    test(
      '''does not warn user of asset or code changes if only dart changes are detected''',
      () async {
        final tempDir = setUpTempDir();
        setUpTempArtifacts(tempDir);
        final exitCode = await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );

        expect(exitCode, ExitCode.success.code);
        verifyNever(
          () => logger.confirm(
            any(
              that: contains(
                '''The Android Archive contains asset changes, which will not be included in the patch.''',
              ),
            ),
          ),
        );
      },
    );

    test(
      '''exits if user decides to not proceed after being warned of non-dart changes''',
      () async {
        when(() => archiveDiffer.containsPotentiallyBreakingAssetDiffs(any()))
            .thenReturn(true);
        when(
          () => logger.confirm(any(that: contains('Continue anyways?'))),
        ).thenReturn(false);

        final tempDir = setUpTempDir();
        setUpTempArtifacts(tempDir);
        final exitCode = await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );

        expect(exitCode, ExitCode.success.code);
        verifyNever(
          () => codePushClientWrapper.publishPatch(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            platform: any(named: 'platform'),
            channelName: any(named: 'channelName'),
            patchArtifactBundles: any(named: 'patchArtifactBundles'),
          ),
        );
      },
    );

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

    test('does not prompt on --force', () async {
      when(() => argResults['force']).thenReturn(true);
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

      expect(exitCode, ExitCode.success.code);
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

      verify(() => codePushClientWrapper.getApp(appId: appId)).called(1);
      verify(
        () => codePushClientWrapper.getRelease(
          appId: appId,
          releaseVersion: version,
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.getReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          architectures: ShorebirdBuildMixin.allAndroidArchitectures,
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
          channelName: channelName,
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      ).called(1);
    });
  });
}

import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
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
  group(ReleaseAarCommand, () {
    const appDisplayName = 'Test App';
    const appId = 'test-app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const androidPackageName = 'com.example.my_flutter_module';
    final appMetadata = AppMetadata(
      appId: appId,
      displayName: appDisplayName,
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const flutterVersionAndRevision = '3.10.6 (83305b5088)';
    const versionName = '1.2.3';
    const versionCode = '1';
    const version = '$versionName+$versionCode';
    const operatingSystem = 'macOS';
    const operatingSystemVersion = '11.0.0';
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
    const releasePlatform = ReleasePlatform.android;
    const buildNumber = '1.0';

    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory shorebirdRoot;
    late Directory projectRoot;
    late Java java;
    late OperatingSystemInterface operatingSystemInterface;
    late Platform platform;
    late Progress progress;
    late Logger logger;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterPubGetProcessResult;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdValidator shorebirdValidator;
    late ReleaseAarCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          javaRef.overrideWith(() => java),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
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
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(ReleaseStatus.draft);
      registerFallbackValue(FakeRelease());
      registerFallbackValue(FakeShorebirdProcess());
    });

    setUp(() {
      argResults = MockArgResults();
      httpClient = MockHttpClient();
      auth = MockAuth();
      codePushClientWrapper = MockCodePushClientWrapper();
      java = MockJava();
      operatingSystemInterface = MockOperatingSystemInterface();
      platform = MockPlatform();
      progress = MockProgress();
      logger = MockLogger();
      flutterBuildProcessResult = MockProcessResult();
      flutterPubGetProcessResult = MockProcessResult();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      projectRoot = Directory.systemTemp.createTempSync();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();

      when(() => auth.client).thenReturn(httpClient);
      when(() => argResults['build-number']).thenReturn(buildNumber);
      when(() => argResults['release-version']).thenReturn(version);
      when(() => argResults['target-platform'])
          .thenReturn(Arch.values.map((a) => a.targetPlatformCliArg).toList());
      when(() => argResults.rest).thenReturn([]);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => operatingSystemInterface.which('flutter'),
      ).thenReturn('/path/to/flutter');
      when(() => platform.operatingSystem).thenReturn(operatingSystem);
      when(() => platform.operatingSystemVersion)
          .thenReturn(operatingSystemVersion);

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
      when(
        () => shorebirdEnv.androidPackageName,
      ).thenReturn(androidPackageName);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);

      when(
        () => shorebirdFlutter.getVersionAndRevision(),
      ).thenAnswer((_) async => flutterVersionAndRevision);
      when(
        () => shorebirdFlutter.installRevision(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async => {});

      when(
        () => flutterBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => flutterPubGetProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);

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
          any(),
          any(that: containsAll(['build', 'aar'])),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((invocation) async {
        return flutterBuildProcessResult;
      });

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
        () => codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          aarPath: any(named: 'aarPath'),
          extractedAarDir: any(named: 'extractedAarDir'),
          architectures: any(named: 'architectures'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          status: any(named: 'status'),
          metadata: any(named: 'metadata'),
        ),
      ).thenAnswer((_) async => {});

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(
        () => ReleaseAarCommand(unzipFn: (_, __) async {}),
      )..testArgResults = argResults;
    });

    test('has correct description', () {
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

      final result = await runWithOverrides(command.run);

      expect(result, ExitCode.config.code);
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
          when(
            () => shorebirdFlutter.getRevisionForVersion(any()),
          ).thenAnswer((_) async => revision);
        });

        test('uses specified flutter version to build', () async {
          setUpProjectRootArtifacts();
          when(
            () => shorebirdProcess.run(
              any(),
              any(that: containsAll(['build', 'aar'])),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer((_) async {
            // Ensure we're using the correct flutter revision.
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
              () => shorebirdFlutter.installRevision(revision: revision),
            ).called(1);
          });
        });
      });
    });

    test('exits with code 70 when building aar fails', () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oops');
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.software.code));
      verify(
        () => shorebirdProcess.run(
          'flutter',
          [
            'build',
            'aar',
            '--no-debug',
            '--no-profile',
            '--build-number=$buildNumber',
          ],
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
      verify(
        () => progress.fail(any(that: contains('Failed to build'))),
      ).called(1);
    });

    test('aborts when user opts out', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      when(
        () => logger.prompt(
          'What is the version of this release?',
          defaultValue: any(named: 'defaultValue'),
        ),
      ).thenAnswer((_) => '1.0.0');
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
      verify(() => logger.info('Aborting.')).called(1);
    });

    test('does not prompt for confirmation if unable to accpet user input',
        () async {
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
      verify(() => logger.success('\n✅ Published Release $version!')).called(1);
      verifyNever(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      );
    });

    test('succeeds when release is successful', () async {
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
      verify(() => logger.success('\n✅ Published Release $version!')).called(1);
      verify(
        () => codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          aarPath: any(
            named: 'aarPath',
            that: endsWith(
              p.join(
                'build',
                'host',
                'outputs',
                'repo',
                'com',
                'example',
                'my_flutter_module',
                'flutter_release',
                '1.0',
                'flutter_release-1.0.aar',
              ),
            ),
          ),
          extractedAarDir: any(
            named: 'extractedAarDir',
            that: endsWith(
              p.join(
                'build',
                'host',
                'outputs',
                'repo',
                'com',
                'example',
                'my_flutter_module',
                'flutter_release',
                '1.0',
                'flutter_release-1.0',
              ),
            ),
          ),
          architectures: any(named: 'architectures'),
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
              xcodeVersion: null,
            ),
          ),
        ),
      ).called(1);
    });

    test('copies aar library to a releases folder', () async {
      setUpProjectRootArtifacts();
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
      expect(
        Directory(p.join(projectRoot.path, 'release')).existsSync(),
        isTrue,
      );
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

    test('does not create new release if existing release is present',
        () async {
      when(
        () => codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
      setUpProjectRootArtifacts();
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
        () => codePushClientWrapper.updateReleaseStatus(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          status: ReleaseStatus.active,
          metadata: any(named: 'metadata'),
        ),
      ).called(1);
    });
  });
}

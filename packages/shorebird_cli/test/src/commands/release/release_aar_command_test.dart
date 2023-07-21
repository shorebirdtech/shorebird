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
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/java.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockDoctor extends Mock implements Doctor {}

class _MockJava extends Mock implements Java {}

class _MockLogger extends Mock implements Logger {}

class _MockPlatform extends Mock implements Platform {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group(ReleaseAarCommand, () {
    const appDisplayName = 'Test App';
    const appId = 'test-app-id';
    const appMetadata = AppMetadata(appId: appId, displayName: appDisplayName);

    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';

    const versionName = '1.2.3';
    const versionCode = '1';
    const version = '$versionName+$versionCode';
    const release = Release(
      id: 0,
      appId: appId,
      version: version,
      flutterRevision: flutterRevision,
      displayName: '1.2.3+1',
      platformStatuses: {},
    );

    const releasePlatform = ReleasePlatform.android;
    const buildNumber = '1.0';
    const noModulePubspecYamlContent = '''
name: example
version: 1.0.0
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  assets:
    - shorebird.yaml''';

    const pubspecYamlContent = '''
name: example
version: 1.0.0
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  module:
    androidX: true
    androidPackage: com.example.my_flutter_module
    iosBundleIdentifier: com.example.myFlutterModule
  assets:
    - shorebird.yaml''';

    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory shorebirdRoot;
    late Doctor doctor;
    late Java java;
    late Platform platform;
    late Progress progress;
    late Logger logger;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterRevisionProcessResult;
    late ReleaseAarCommand command;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          javaRef.overrideWith(() => java),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
        },
      );
    }

    Directory setUpTempDir({bool includeModule = true}) {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(
        includeModule ? pubspecYamlContent : noModulePubspecYamlContent,
      );
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('app_id: $appId');
      return tempDir;
    }

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
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(ReleaseStatus.draft);
    });

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      codePushClientWrapper = _MockCodePushClientWrapper();
      doctor = _MockDoctor();
      java = _MockJava();
      platform = _MockPlatform();
      progress = _MockProgress();
      logger = _MockLogger();
      flutterBuildProcessResult = _MockProcessResult();
      flutterRevisionProcessResult = _MockProcessResult();
      flutterValidator = _MockShorebirdFlutterValidator();
      shorebirdProcess = _MockShorebirdProcess();
      shorebirdRoot = Directory.systemTemp.createTempSync();

      registerFallbackValue(release);
      registerFallbackValue(shorebirdProcess);

      when(() => auth.client).thenReturn(httpClient);
      when(() => argResults['build-number']).thenReturn(buildNumber);
      when(() => argResults['release-version']).thenReturn(versionName);
      when(() => argResults.rest).thenReturn([]);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);

      when(() => platform.script).thenReturn(
        Uri.file(
          p.join(
            shorebirdRoot.path,
            'bin',
            'cache',
            'shorebird.snapshot',
          ),
        ),
      );

      when(() => flutterBuildProcessResult.exitCode)
          .thenReturn(ExitCode.success.code);

      when(
        () => flutterRevisionProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => flutterRevisionProcessResult.stdout,
      ).thenReturn(flutterRevision);

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
        () => shorebirdProcess.run(
          'git',
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => flutterRevisionProcessResult);

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
        () => codePushClientWrapper.ensureReleaseHasNoArtifacts(
          appId: any(named: 'appId'),
          existingRelease: any(named: 'existingRelease'),
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
        ),
      ).thenAnswer((_) async => {});

      when(() => doctor.androidCommandValidators)
          .thenReturn([flutterValidator]);
      when(flutterValidator.validate).thenAnswer((_) async => []);

      command = runWithOverrides(
        () => ReleaseAarCommand(unzipFn: (_, __) async {}),
      )..testArgResults = argResults;
    });

    test('has correct description', () {
      expect(command.description, isNotEmpty);
    });

    test('throws config error when shorebird is not initialized', () async {
      final tempDir = Directory.systemTemp.createTempSync();

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      verify(
        () => logger.err(
          'Shorebird is not initialized. Did you run "shorebird init"?',
        ),
      ).called(1);
      expect(exitCode, ExitCode.config.code);
    });

    test('exits with no user when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      final tempDir = setUpTempDir(includeModule: false);

      final result = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, equals(ExitCode.noUser.code));
      verify(
        () => logger.err(any(that: contains('You must be logged in to run'))),
      ).called(1);
    });

    test('exits with 78 if no pubspec.yaml exists', () async {
      final tempDir = Directory.systemTemp.createTempSync();

      final result = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, ExitCode.config.code);
    });

    test('exits with 78 if no module entry exists in pubspec.yaml', () async {
      final tempDir = setUpTempDir(includeModule: false);

      final result = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, ExitCode.config.code);
    });

    test('exits with code 70 when building aar fails', () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oops');
      final tempDir = setUpTempDir();

      final result = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

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
      verify(() => progress.fail(any(that: contains('Failed to build'))))
          .called(1);
    });

    test('aborts when user opts out', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      when(
        () => logger.prompt(
          'What is the version of this release?',
          defaultValue: any(named: 'defaultValue'),
        ),
      ).thenAnswer((_) => '1.0.0');
      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.success.code);
      verify(() => logger.info('Aborting.')).called(1);
    });

    test('throws error when unable to detect flutter revision', () async {
      const error = 'oops';
      when(() => flutterRevisionProcessResult.exitCode).thenReturn(1);
      when(() => flutterRevisionProcessResult.stderr).thenReturn(error);
      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.software.code);
      verify(
        () => progress.fail(
          'Exception: Unable to determine flutter revision: $error',
        ),
      ).called(1);
    });

    test('does not prompt for confirmation when --force is used', () async {
      when(() => argResults['force']).thenReturn(true);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
      verify(() => logger.success('\n✅ Published Release!')).called(1);
      verifyNever(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      );
    });

    test('succeeds when release is successful', () async {
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
      verify(() => logger.success('\n✅ Published Release!')).called(1);
      verify(
        () => codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          aarPath: any(
            named: 'aarPath',
            that: endsWith(
              '/build/host/outputs/repo/com/example/my_flutter_module/flutter_release/1.0/flutter_release-1.0.aar',
            ),
          ),
          extractedAarDir: any(
            named: 'extractedAarDir',
            that: endsWith(
              'build/host/outputs/repo/com/example/my_flutter_module/flutter_release/1.0/flutter_release-1.0',
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
        ),
      ).called(1);
    });

    test(
        'succeeds when release is successful '
        'with flavors and target', () async {
      const flavor = 'development';
      when(() => argResults['flavor']).thenReturn(flavor);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('''
app_id: productionAppId
flavors:
  development: $appId''');

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
      verify(() => logger.success('\n✅ Published Release!')).called(1);
      final capturedArgs = verify(
        () => shorebirdProcess.run(
          'flutter',
          captureAny(),
          runInShell: true,
        ),
      ).captured.first as List<String>;
      expect(capturedArgs, contains('--flavor=$flavor'));
      verify(
        () => codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          aarPath: any(
            named: 'aarPath',
            that: endsWith(
              '/build/host/outputs/repo/com/example/my_flutter_module/flutter_release/1.0/flutter_release-1.0.aar',
            ),
          ),
          extractedAarDir: any(
            named: 'extractedAarDir',
            that: endsWith(
              'build/host/outputs/repo/com/example/my_flutter_module/flutter_release/1.0/flutter_release-1.0',
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
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

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
        ),
      ).called(1);
    });

    test('prints flutter validation warnings', () async {
      when(flutterValidator.validate).thenAnswer(
        (_) async => [
          const ValidationIssue(
            severity: ValidationIssueSeverity.warning,
            message: 'Flutter issue 1',
          ),
          const ValidationIssue(
            severity: ValidationIssueSeverity.warning,
            message: 'Flutter issue 2',
          ),
        ],
      );
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
      verify(() => logger.success('\n✅ Published Release!')).called(1);
      verify(
        () => logger.info(any(that: contains('Flutter issue 1'))),
      ).called(1);
      verify(
        () => logger.info(any(that: contains('Flutter issue 2'))),
      ).called(1);
    });

    test('aborts if validation errors are present', () async {
      when(flutterValidator.validate).thenAnswer(
        (_) async => [
          const ValidationIssue(
            severity: ValidationIssueSeverity.error,
            message: 'There was an issue',
          ),
        ],
      );

      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.config.code));
      verify(() => logger.err('Aborting due to validation errors.')).called(1);
      verifyNever(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          status: ReleaseStatus.active,
        ),
      );
    });
  });
}

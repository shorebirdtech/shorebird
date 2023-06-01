import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group(ReleaseAndroidArchiveCommand, () {
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
    );

    const arch = 'aarch64';
    const platform = 'android';
    const releaseArtifact = ReleaseArtifact(
      id: 0,
      releaseId: 0,
      arch: arch,
      platform: platform,
      hash: '#',
      size: 42,
      url: 'https://example.com',
    );

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
    late Progress progress;
    late Logger logger;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterRevisionProcessResult;
    late CodePushClient codePushClient;
    late ReleaseAndroidArchiveCommand command;
    late Uri? capturedHostedUri;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;

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

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      progress = _MockProgress();
      logger = _MockLogger();
      flutterBuildProcessResult = _MockProcessResult();
      flutterRevisionProcessResult = _MockProcessResult();
      codePushClient = _MockCodePushClient();
      flutterValidator = _MockShorebirdFlutterValidator();
      shorebirdProcess = _MockShorebirdProcess();
      command = ReleaseAndroidArchiveCommand(
        auth: auth,
        buildCodePushClient: ({
          required http.Client httpClient,
          Uri? hostedUri,
        }) {
          capturedHostedUri = hostedUri;
          return codePushClient;
        },
        unzipFn: (_, __) async {},
        logger: logger,
        validators: [flutterValidator],
      )
        ..testArgResults = argResults
        ..testProcess = shorebirdProcess
        ..testEngineConfig = const EngineConfig.empty();

      registerFallbackValue(shorebirdProcess);

      when(() => auth.client).thenReturn(httpClient);
      when(() => argResults['build-number']).thenReturn(buildNumber);
      when(() => argResults['release-version']).thenReturn(versionName);
      when(() => argResults.rest).thenReturn([]);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);

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
        () => codePushClient.getApps(),
      ).thenAnswer((_) async => [appMetadata]);
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => [release]);
      when(
        () => codePushClient.createRelease(
          appId: any(named: 'appId'),
          version: any(named: 'version'),
          flutterRevision: any(named: 'flutterRevision'),
        ),
      ).thenAnswer((_) async => release);
      when(
        () => codePushClient.createReleaseArtifact(
          artifactPath: any(named: 'artifactPath'),
          releaseId: any(named: 'releaseId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
          hash: any(named: 'hash'),
        ),
      ).thenAnswer((_) async => releaseArtifact);

      when(() => flutterValidator.validate(any())).thenAnswer((_) async => []);
    });

    test('has correct description', () {
      expect(command.description, isNotEmpty);
    });

    test('throws config error when shorebird is not initialized', () async {
      final tempDir = Directory.systemTemp.createTempSync();

      final exitCode = await IOOverrides.runZoned(
        command.run,
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
        () async => command.run(),
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
        () async => command.run(),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, ExitCode.config.code);
    });

    test('exits with 78 if no module entry exists in pubspec.yaml', () async {
      final tempDir = setUpTempDir(includeModule: false);

      final result = await IOOverrides.runZoned(
        () async => command.run(),
        getCurrentDirectory: () => tempDir,
      );

      expect(result, ExitCode.config.code);
    });

    test('exits with code 70 when building aar fails', () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oops');
      final tempDir = setUpTempDir();

      final result = await IOOverrides.runZoned(
        () async => command.run(),
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

    test('throws error when fetching apps fails.', () async {
      const error = 'something went wrong';
      when(() => codePushClient.getApps()).thenThrow(error);
      final tempDir = setUpTempDir();

      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );

      verify(() => progress.fail(error)).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws error when app does not exist.', () async {
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(appDisplayName);
      when(() => codePushClient.getApps()).thenAnswer((_) async => []);
      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.err(
          '''
Could not find app with id: "$appId".
Did you forget to run "shorebird init"?''',
        ),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
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
      // setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.success.code);
      verify(() => logger.info('Aborting.')).called(1);
    });

    test('throws error when fetching releases fails.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenThrow(error);
      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => progress.fail(error)).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws error when unable to detect flutter revision', () async {
      const error = 'oops';
      when(() => flutterRevisionProcessResult.exitCode).thenReturn(1);
      when(() => flutterRevisionProcessResult.stderr).thenReturn(error);
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      final tempDir = setUpTempDir();
      // setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.software.code);
      verify(
        () => progress.fail(
          'Exception: Unable to determine flutter revision: $error',
        ),
      ).called(1);
    });

    test('throws error when creating release fails.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      when(
        () => codePushClient.createRelease(
          appId: any(named: 'appId'),
          version: any(named: 'version'),
          flutterRevision: any(named: 'flutterRevision'),
          displayName: any(named: 'displayName'),
        ),
      ).thenThrow(error);
      final tempDir = setUpTempDir();
      // setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => progress.fail(error)).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('logs message when uploading release artifact that already exists.',
        () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      when(
        () => codePushClient.createReleaseArtifact(
          artifactPath: any(named: 'artifactPath'),
          releaseId: any(named: 'releaseId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
          hash: any(named: 'hash'),
        ),
      ).thenThrow(const CodePushConflictException(message: error));
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );

      // 1 for each arch, 1 for the aar
      final numArtifactsUploaded = Arch.values.length + 1;
      verify(
        () => codePushClient.createRelease(
          appId: appId,
          version: versionName,
          flutterRevision: flutterRevision,
        ),
      ).called(1);
      verify(
        () => logger.info(any(that: contains('already exists'))),
      ).called(numArtifactsUploaded);
      verifyNever(() => progress.fail(error));
      expect(exitCode, ExitCode.success.code);
    });

    test('logs message when uploading aar that already exists.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      when(
        () => codePushClient.createReleaseArtifact(
          artifactPath: any(named: 'artifactPath', that: endsWith('.aar')),
          releaseId: any(named: 'releaseId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
          hash: any(named: 'hash'),
        ),
      ).thenThrow(const CodePushConflictException(message: error));
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );

      verify(
        () => logger.info(
          any(that: contains('aar artifact already exists, continuing...')),
        ),
      ).called(1);
      verify(
        () => codePushClient.createRelease(
          appId: appId,
          version: versionName,
          flutterRevision: flutterRevision,
        ),
      ).called(1);
      verifyNever(() => progress.fail(error));
      expect(exitCode, ExitCode.success.code);
    });

    test('throws error when uploading release artifact fails.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      when(
        () => codePushClient.createReleaseArtifact(
          artifactPath: any(named: 'artifactPath'),
          releaseId: any(named: 'releaseId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
          hash: any(named: 'hash'),
        ),
      ).thenThrow(error);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );

      verify(
        () => progress
            .fail(any(that: stringContainsInOrder(['libapp.so', error]))),
      ).called(1);
      verify(
        () => codePushClient.createRelease(
          appId: appId,
          version: versionName,
          flutterRevision: flutterRevision,
        ),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws error when uploading aar fails', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      when(
        () => codePushClient.createReleaseArtifact(
          artifactPath: any(named: 'artifactPath', that: endsWith('.aar')),
          releaseId: any(named: 'releaseId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
          hash: any(named: 'hash'),
        ),
      ).thenThrow(error);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );

      verify(
        () => progress.fail(
          any(
            that: stringContainsInOrder(
              ['flutter_release-$buildNumber.aar', error],
            ),
          ),
        ),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('does not prompt for confirmation when --force is used', () async {
      when(() => argResults['force']).thenReturn(true);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );

      verify(() => logger.success('\n✅ Published Release!')).called(1);
      expect(exitCode, ExitCode.success.code);
      expect(capturedHostedUri, isNull);
      verifyNever(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      );
    });

    test('succeeds when release is successful', () async {
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.success('\n✅ Published Release!')).called(1);
      verify(
        () => codePushClient.createReleaseArtifact(
          artifactPath: any(named: 'artifactPath', that: endsWith('.aar')),
          releaseId: any(named: 'releaseId'),
          arch: 'aar',
          platform: 'android',
          hash: any(named: 'hash'),
        ),
      ).called(1);
      expect(exitCode, ExitCode.success.code);
      expect(capturedHostedUri, isNull);
    });

    test(
        'succeeds when release is successful '
        'with flavors and target', () async {
      const flavor = 'development';
      when(() => argResults['flavor']).thenReturn(flavor);
      final tempDir = setUpTempDir();
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('''
app_id: productionAppId
flavors:
  development: $appId''');
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.success('\n✅ Published Release!')).called(1);
      verify(
        () => codePushClient.createReleaseArtifact(
          artifactPath: any(named: 'artifactPath', that: endsWith('.aar')),
          releaseId: any(named: 'releaseId'),
          arch: 'aar',
          platform: 'android',
          hash: any(named: 'hash'),
        ),
      ).called(1);
      expect(exitCode, ExitCode.success.code);
      expect(capturedHostedUri, isNull);
    });

    test('prints flutter validation warnings', () async {
      when(() => flutterValidator.validate(any())).thenAnswer(
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
        command.run,
        getCurrentDirectory: () => tempDir,
      );

      verify(() => logger.success('\n✅ Published Release!')).called(1);
      expect(exitCode, ExitCode.success.code);
      expect(capturedHostedUri, isNull);
      verify(
        () => logger.info(any(that: contains('Flutter issue 1'))),
      ).called(1);
      verify(
        () => logger.info(any(that: contains('Flutter issue 2'))),
      ).called(1);
    });

    test('aborts if validation errors are present', () async {
      when(() => flutterValidator.validate(any())).thenAnswer(
        (_) async => [
          const ValidationIssue(
            severity: ValidationIssueSeverity.error,
            message: 'There was an issue',
          ),
        ],
      );

      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.config.code));
      verify(() => logger.err('Aborting due to validation errors.')).called(1);
    });
  });
}

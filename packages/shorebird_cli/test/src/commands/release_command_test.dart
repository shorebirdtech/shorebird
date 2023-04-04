import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockAccessCredentials extends Mock implements AccessCredentials {}

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ProcessResult {}

class _MockCodePushClient extends Mock implements CodePushClient {}

void main() {
  group('release', () {
    const appId = 'test-app-id';
    const version = '1.2.3';
    const appDisplayName = 'Test App';
    const arch = 'aarch64';
    const platform = 'android';
    const appMetadata = AppMetadata(appId: appId, displayName: appDisplayName);
    const release = Release(
      id: 0,
      appId: appId,
      version: version,
      displayName: '1.2.3',
    );
    const releaseArtifact = ReleaseArtifact(
      id: 0,
      releaseId: 0,
      arch: arch,
      platform: platform,
      hash: '#',
      size: 42,
      url: 'https://example.com',
    );

    const pubspecYamlContent = '''
name: example
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  assets:
    - shorebird.yaml''';

    final credentials = _MockAccessCredentials();

    late ArgResults argResults;
    late Directory applicationConfigHome;
    late http.Client httpClient;
    late Auth auth;
    late Progress progress;
    late Logger logger;
    late ProcessResult processResult;
    late CodePushClient codePushClient;
    late ReleaseCommand command;
    late Uri? capturedHostedUri;

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

    setUp(() {
      argResults = _MockArgResults();
      applicationConfigHome = Directory.systemTemp.createTempSync();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      progress = _MockProgress();
      logger = _MockLogger();
      processResult = _MockProcessResult();
      codePushClient = _MockCodePushClient();
      command = ReleaseCommand(
        auth: auth,
        buildCodePushClient: ({
          required http.Client httpClient,
          Uri? hostedUri,
        }) {
          capturedHostedUri = hostedUri;
          return codePushClient;
        },
        runProcess: (
          executable,
          arguments, {
          bool runInShell = false,
          String? workingDirectory,
        }) async {
          return processResult;
        },
        logger: logger,
      )..testArgResults = argResults;
      testApplicationConfigHome = (_) => applicationConfigHome.path;

      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['arch']).thenReturn(arch);
      when(() => argResults['platform']).thenReturn(platform);
      when(() => auth.credentials).thenReturn(credentials);
      when(() => auth.client).thenReturn(httpClient);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.confirm(any())).thenReturn(true);
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(version);
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      when(
        () => codePushClient.downloadEngine(revision: any(named: 'revision')),
      ).thenAnswer((_) async => Uint8List.fromList([]));
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

    test('throws no user error when session does not exist', () async {
      when(() => auth.credentials).thenReturn(null);
      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => command.run(),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.noUser.code));
    });

    test('exits with code 70 when pulling engine fails', () async {
      when(
        () => codePushClient.downloadEngine(revision: any(named: 'revision')),
      ).thenThrow(Exception('oops'));
      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.software.code));
    });

    test('exits with code 70 when building fails', () async {
      when(() => processResult.exitCode).thenReturn(1);
      when(() => processResult.stderr).thenReturn('oops');
      when(
        () => codePushClient.downloadEngine(revision: any(named: 'revision')),
      ).thenAnswer(
        (_) async => Uint8List.fromList(ZipEncoder().encode(Archive())!),
      );

      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () async => command.run(),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.software.code));
    });

    test('throws software error when artifact is not found (default).',
        () async {
      final tempDir = setUpTempDir();
      Directory(
        p.join(command.shorebirdEnginePath, 'engine'),
      ).createSync(recursive: true);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.err(any(that: contains('Artifact not found:'))),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws error when fetching apps fails.', () async {
      const error = 'something went wrong';
      when(() => codePushClient.getApps()).thenThrow(error);
      final tempDir = setUpTempDir();
      Directory(
        p.join(command.shorebirdEnginePath, 'engine'),
      ).createSync(recursive: true);
      final artifactPath = p.join(
        tempDir.path,
        'build',
        'app',
        'intermediates',
        'stripped_native_libs',
        'release',
        'out',
        'lib',
        'arm64-v8a',
        'libapp.so',
      );
      File(artifactPath).createSync(recursive: true);
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
      Directory(
        p.join(command.shorebirdEnginePath, 'engine'),
      ).createSync(recursive: true);
      final artifactPath = p.join(
        tempDir.path,
        'build',
        'app',
        'intermediates',
        'stripped_native_libs',
        'release',
        'out',
        'lib',
        'arm64-v8a',
        'libapp.so',
      );
      File(artifactPath).createSync(recursive: true);
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
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(appDisplayName);
      final tempDir = setUpTempDir();
      Directory(
        p.join(command.shorebirdEnginePath, 'engine'),
      ).createSync(recursive: true);
      final artifactPath = p.join(
        tempDir.path,
        'build',
        'app',
        'intermediates',
        'stripped_native_libs',
        'release',
        'out',
        'lib',
        'arm64-v8a',
        'libapp.so',
      );
      File(artifactPath).createSync(recursive: true);
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
      Directory(
        p.join(command.shorebirdEnginePath, 'engine'),
      ).createSync(recursive: true);
      final artifactPath = p.join(
        tempDir.path,
        'build',
        'app',
        'intermediates',
        'stripped_native_libs',
        'release',
        'out',
        'lib',
        'arm64-v8a',
        'libapp.so',
      );
      File(artifactPath).createSync(recursive: true);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => progress.fail(error)).called(1);
      expect(exitCode, ExitCode.software.code);
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
          displayName: any(named: 'displayName'),
        ),
      ).thenThrow(error);
      final tempDir = setUpTempDir();
      Directory(
        p.join(command.shorebirdEnginePath, 'engine'),
      ).createSync(recursive: true);
      final artifactPath = p.join(
        tempDir.path,
        'build',
        'app',
        'intermediates',
        'stripped_native_libs',
        'release',
        'out',
        'lib',
        'arm64-v8a',
        'libapp.so',
      );
      File(artifactPath).createSync(recursive: true);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => progress.fail(error)).called(1);
      expect(exitCode, ExitCode.software.code);
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
      Directory(
        p.join(command.shorebirdEnginePath, 'engine'),
      ).createSync(recursive: true);
      final artifactPath = p.join(
        tempDir.path,
        'build',
        'app',
        'intermediates',
        'stripped_native_libs',
        'release',
        'out',
        'lib',
        'arm64-v8a',
        'libapp.so',
      );
      File(artifactPath).createSync(recursive: true);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => progress.fail(error)).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('succeeds when release is successful', () async {
      final tempDir = setUpTempDir();
      Directory(
        p.join(command.shorebirdEnginePath, 'engine'),
      ).createSync(recursive: true);
      final artifactPath = p.join(
        tempDir.path,
        'build',
        'app',
        'intermediates',
        'stripped_native_libs',
        'release',
        'out',
        'lib',
        'arm64-v8a',
        'libapp.so',
      );
      File(artifactPath).createSync(recursive: true);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.success('\n✅ Published Release!')).called(1);
      expect(exitCode, ExitCode.success.code);
      expect(capturedHostedUri, isNull);
    });
  });
}

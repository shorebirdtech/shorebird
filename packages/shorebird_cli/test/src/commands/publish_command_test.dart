import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/session.dart';
import 'package:shorebird_cli/src/commands/publish_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ProcessResult {}

class _MockCodePushClient extends Mock implements CodePushClient {}

void main() {
  group('publish', () {
    const session = Session(apiKey: 'test-api-key');
    const appId = 'test-app-id';
    const version = '1.2.3';
    const appDisplayName = 'Test App';
    const app = App(id: appId, displayName: appDisplayName);
    const appMetadata = AppMetadata(appId: appId, displayName: appDisplayName);
    const artifact = Artifact(
      id: 0,
      patchId: 0,
      arch: 'aarch64',
      platform: 'android',
      hash: '#',
      url: 'https://example.com',
    );
    const release = Release(
      id: 0,
      appId: appId,
      version: version,
      displayName: '1.2.3',
    );
    const patch = Patch(id: 0, number: 1);
    const channel = Channel(id: 0, appId: appId, name: 'stable');
    const pubspecYamlContent = '''
name: example
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  assets:
    - shorebird.yaml''';

    late ArgResults argResults;
    late Auth auth;
    late Progress progress;
    late Logger logger;
    late ProcessResult processResult;
    late CodePushClient codePushClient;
    late PublishCommand command;
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
      auth = _MockAuth();
      progress = _MockProgress();
      logger = _MockLogger();
      processResult = _MockProcessResult();
      codePushClient = _MockCodePushClient();
      command = PublishCommand(
        auth: auth,
        buildCodePushClient: ({required String apiKey, Uri? hostedUri}) {
          capturedHostedUri = hostedUri;
          return codePushClient;
        },
        runProcess: (executable, arguments, {bool runInShell = false}) async {
          return processResult;
        },
        logger: logger,
      )..testArgResults = argResults;

      when(() => argResults.rest).thenReturn([]);
      when(() => auth.currentSession).thenReturn(session);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      when(
        () => codePushClient.downloadEngine(revision: any(named: 'revision')),
      ).thenAnswer((_) async => Uint8List.fromList([]));
      when(
        () => codePushClient.getApps(),
      ).thenAnswer((_) async => [appMetadata]);
      when(
        () => codePushClient.getChannels(appId: any(named: 'appId')),
      ).thenAnswer((_) async => [channel]);
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => [release]);
      when(
        () => codePushClient.createApp(displayName: any(named: 'displayName')),
      ).thenAnswer((_) async => app);
      when(
        () => codePushClient.createChannel(
          appId: any(named: 'appId'),
          channel: any(named: 'channel'),
        ),
      ).thenAnswer((_) async => channel);
      when(
        () => codePushClient.createRelease(
          appId: any(named: 'appId'),
          version: any(named: 'version'),
        ),
      ).thenAnswer((_) async => release);
      when(
        () => codePushClient.createPatch(releaseId: any(named: 'releaseId')),
      ).thenAnswer((_) async => patch);
      when(
        () => codePushClient.createArtifact(
          artifactPath: any(named: 'artifactPath'),
          patchId: any(named: 'patchId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
          hash: any(named: 'hash'),
        ),
      ).thenAnswer((_) async => artifact);
      when(
        () => codePushClient.promotePatch(
          patchId: any(named: 'patchId'),
          channelId: any(named: 'channelId'),
        ),
      ).thenAnswer((_) async {});
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
      when(() => auth.currentSession).thenReturn(null);
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
      when(() => auth.currentSession).thenReturn(session);
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
      when(() => auth.currentSession).thenReturn(session);

      final tempDir = setUpTempDir();
      Directory(
        '${tempDir.path}/.shorebird/engine',
      ).createSync(recursive: true);
      Directory(
        '${tempDir.path}/.shorebird/cache',
      ).createSync(recursive: true);
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
        '${tempDir.path}/.shorebird/engine',
      ).createSync(recursive: true);
      Directory(
        '${tempDir.path}/.shorebird/cache',
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
      when(
        () => codePushClient.getApps(),
      ).thenThrow(error);
      final tempDir = setUpTempDir();
      Directory(
        '${tempDir.path}/.shorebird/engine',
      ).createSync(recursive: true);
      Directory(
        '${tempDir.path}/.shorebird/cache',
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

    test('throws error when creating apps fails.', () async {
      const error = 'something went wrong';
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(appDisplayName);
      when(() => codePushClient.getApps()).thenAnswer((_) async => []);
      when(
        () => codePushClient.createApp(displayName: any(named: 'displayName')),
      ).thenThrow(error);
      final tempDir = setUpTempDir();
      Directory(
        '${tempDir.path}/.shorebird/engine',
      ).createSync(recursive: true);
      Directory(
        '${tempDir.path}/.shorebird/cache',
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
      verify(() => logger.err(error)).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('aborts when user opts out', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(appDisplayName);
      when(() => codePushClient.getApps()).thenAnswer((_) async => []);
      final tempDir = setUpTempDir();
      Directory(
        '${tempDir.path}/.shorebird/engine',
      ).createSync(recursive: true);
      Directory(
        '${tempDir.path}/.shorebird/cache',
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
        '${tempDir.path}/.shorebird/engine',
      ).createSync(recursive: true);
      Directory(
        '${tempDir.path}/.shorebird/cache',
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
        '${tempDir.path}/.shorebird/engine',
      ).createSync(recursive: true);
      Directory(
        '${tempDir.path}/.shorebird/cache',
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

    test('throws error when creating patch fails.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      when(
        () => codePushClient.createPatch(releaseId: any(named: 'releaseId')),
      ).thenThrow(error);
      final tempDir = setUpTempDir();
      Directory(
        '${tempDir.path}/.shorebird/engine',
      ).createSync(recursive: true);
      Directory(
        '${tempDir.path}/.shorebird/cache',
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

    test('throws error when uploading artifact fails.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      when(
        () => codePushClient.createArtifact(
          artifactPath: any(named: 'artifactPath'),
          patchId: any(named: 'patchId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
          hash: any(named: 'hash'),
        ),
      ).thenThrow(error);
      final tempDir = setUpTempDir();
      Directory(
        '${tempDir.path}/.shorebird/engine',
      ).createSync(recursive: true);
      Directory(
        '${tempDir.path}/.shorebird/cache',
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

    test('throws error when fetching channels fails.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.getChannels(appId: any(named: 'appId')),
      ).thenThrow(error);
      final tempDir = setUpTempDir();
      Directory(
        '${tempDir.path}/.shorebird/engine',
      ).createSync(recursive: true);
      Directory(
        '${tempDir.path}/.shorebird/cache',
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

    test('throws error when creating channel fails.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.getChannels(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      when(
        () => codePushClient.createChannel(
          appId: any(named: 'appId'),
          channel: any(named: 'channel'),
        ),
      ).thenThrow(error);
      final tempDir = setUpTempDir();
      Directory(
        '${tempDir.path}/.shorebird/engine',
      ).createSync(recursive: true);
      Directory(
        '${tempDir.path}/.shorebird/cache',
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

    test('throws error when promoting patch fails.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.getChannels(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      when(
        () => codePushClient.promotePatch(
          patchId: any(named: 'patchId'),
          channelId: any(named: 'channelId'),
        ),
      ).thenThrow(error);
      final tempDir = setUpTempDir();
      Directory(
        '${tempDir.path}/.shorebird/engine',
      ).createSync(recursive: true);
      Directory(
        '${tempDir.path}/.shorebird/cache',
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

    test('succeeds when publish is successful', () async {
      final tempDir = setUpTempDir();
      Directory(
        '${tempDir.path}/.shorebird/engine',
      ).createSync(recursive: true);
      Directory(
        '${tempDir.path}/.shorebird/cache',
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
      verify(() => logger.success('\n✅ Published Successfully!')).called(1);
      expect(exitCode, ExitCode.success.code);
      expect(capturedHostedUri, isNull);
    });

    test('succeeds when publish is successful using custom base_url', () async {
      final tempDir = setUpTempDir();
      const baseUrl = 'https://example.com';
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync(
        '''
app_id: $appId
base_url: $baseUrl''',
      );
      Directory(
        '${tempDir.path}/.shorebird/engine',
      ).createSync(recursive: true);
      Directory(
        '${tempDir.path}/.shorebird/cache',
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
      await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(capturedHostedUri, equals(Uri.parse(baseUrl)));
    });
  });
}

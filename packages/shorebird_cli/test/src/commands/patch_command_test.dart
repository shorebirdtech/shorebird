import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/patch_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ProcessResult {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

void main() {
  group('patch', () {
    const appId = 'test-app-id';
    const version = '1.2.3';
    const arch = 'aarch64';
    const platform = 'android';
    const channelName = 'stable';
    const appDisplayName = 'Test App';
    const appMetadata = AppMetadata(appId: appId, displayName: appDisplayName);
    const patchArtifact = PatchArtifact(
      id: 0,
      patchId: 0,
      arch: arch,
      platform: platform,
      hash: '#',
      size: 42,
      url: 'https://example.com',
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
    const release = Release(
      id: 0,
      appId: appId,
      version: version,
      displayName: '1.2.3',
    );
    const patch = Patch(id: 0, number: 1);
    const channel = Channel(id: 0, appId: appId, name: channelName);
    const pubspecYamlContent = '''
name: example
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  assets:
    - shorebird.yaml''';

    late ArgResults argResults;
    late Directory applicationConfigHome;
    late Auth auth;
    late Progress progress;
    late Logger logger;
    late ProcessResult flutterBuildProcessResult;
    late ProcessResult patchProcessResult;
    late http.Client httpClient;
    late CodePushClient codePushClient;
    late PatchCommand command;
    late Uri? capturedHostedUri;
    late ShorebirdFlutterValidator flutterValidator;

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

    setUpAll(() {
      registerFallbackValue(_FakeBaseRequest());
    });

    setUp(() {
      argResults = _MockArgResults();
      applicationConfigHome = Directory.systemTemp.createTempSync();
      auth = _MockAuth();
      progress = _MockProgress();
      logger = _MockLogger();
      flutterBuildProcessResult = _MockProcessResult();
      patchProcessResult = _MockProcessResult();
      httpClient = _MockHttpClient();
      codePushClient = _MockCodePushClient();
      flutterValidator = _MockShorebirdFlutterValidator();
      command = PatchCommand(
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
          Map<String, String>? environment,
          String? workingDirectory,
          bool useVendedFlutter = true,
        }) async {
          if (executable == 'flutter') return flutterBuildProcessResult;
          if (executable.endsWith('patch')) return patchProcessResult;
          return _MockProcessResult();
        },
        logger: logger,
        httpClient: httpClient,
        flutterValidator: flutterValidator,
      )..testArgResults = argResults;
      testApplicationConfigHome = (_) => applicationConfigHome.path;

      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['arch']).thenReturn(arch);
      when(() => argResults['platform']).thenReturn(platform);
      when(() => argResults['channel']).thenReturn(channelName);
      when(() => argResults['dry-run']).thenReturn(false);
      when(() => argResults['force']).thenReturn(false);
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
        () => codePushClient.getReleaseArtifact(
          releaseId: any(named: 'releaseId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async => releaseArtifact);
      when(
        () => codePushClient.createChannel(
          appId: any(named: 'appId'),
          channel: any(named: 'channel'),
        ),
      ).thenAnswer((_) async => channel);
      when(
        () => codePushClient.createPatch(releaseId: any(named: 'releaseId')),
      ).thenAnswer((_) async => patch);
      when(
        () => codePushClient.createPatchArtifact(
          artifactPath: any(named: 'artifactPath'),
          patchId: any(named: 'patchId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
          hash: any(named: 'hash'),
        ),
      ).thenAnswer((_) async => patchArtifact);
      when(
        () => codePushClient.promotePatch(
          patchId: any(named: 'patchId'),
          channelId: any(named: 'channelId'),
        ),
      ).thenAnswer((_) async {});
      when(() => flutterValidator.validate()).thenAnswer((_) async => []);
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

    test('throws no user error when user is not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
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
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oops');

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

    test(
        'exits with usage code when '
        'both --dry-run and --force are specified', () async {
      when(() => argResults['dry-run']).thenReturn(true);
      when(() => argResults['force']).thenReturn(true);
      final tempDir = setUpTempDir();
      Directory(
        p.join(command.shorebirdEnginePath, 'engine'),
      ).createSync(recursive: true);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.usage.code));
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

    test('throws error when app does not exist fails.', () async {
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

    test('throws error when release does not exist.', () async {
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
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
Release not found: "$version"

Patches can only be published for existing releases.
Please create a release using "shorebird release" and try again.
''',
        ),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws error when release artifact cannot be retrieved.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.getReleaseArtifact(
          releaseId: any(named: 'releaseId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
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

    test('throws error when release artifact does not exist.', () async {
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          const Stream.empty(),
          HttpStatus.notFound,
          reasonPhrase: 'Not Found',
        ),
      );
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
        () => progress.fail(
          'Exception: Failed to download release artifact: 404 Not Found',
        ),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws error when creating diff fails', () async {
      const error = 'oops something went wrong';
      when(() => patchProcessResult.exitCode).thenReturn(1);
      when(() => patchProcessResult.stderr).thenReturn(error);
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
        () => progress.fail('Exception: Failed to create diff: $error'),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('does not create patch on --dry-run', () async {
      when(() => argResults['dry-run']).thenReturn(true);
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
      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(
        () => codePushClient.createPatch(releaseId: any(named: 'releaseId')),
      );
      verify(() => logger.info('No issues detected.')).called(1);
    });

    test('does not prompt on --force', () async {
      when(() => argResults['force']).thenReturn(true);
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
      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(() => logger.confirm(any()));
      verify(
        () => codePushClient.createPatch(releaseId: any(named: 'releaseId')),
      ).called(1);
    });

    test('throws error when creating patch fails.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.createPatch(releaseId: any(named: 'releaseId')),
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

    test('throws error when uploading patch artifact fails.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.createPatchArtifact(
          artifactPath: any(named: 'artifactPath'),
          patchId: any(named: 'patchId'),
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

    test('throws error when fetching channels fails.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.getChannels(appId: any(named: 'appId')),
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

    test('succeeds when patch is successful', () async {
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
      verify(() => logger.success('\n✅ Published Patch!')).called(1);
      expect(exitCode, ExitCode.success.code);
      expect(capturedHostedUri, isNull);
    });

    test('succeeds when patch is successful using custom base_url', () async {
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
      await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(capturedHostedUri, equals(Uri.parse(baseUrl)));
    });

    test('prints flutter validation warnings', () async {
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
      when(() => flutterValidator.validate()).thenAnswer(
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

      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => logger.info(any(that: contains('Flutter issue 1'))),
      ).called(1);
      verify(
        () => logger.info(any(that: contains('Flutter issue 2'))),
      ).called(1);
    });
  });
}

import 'dart:io' hide Platform;

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockIpaReader extends Mock implements IpaReader {}

class _MockIpa extends Mock implements Ipa {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _FakeShorebirdProcess extends Fake implements ShorebirdProcess {}

void main() {
  const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
  const appId = 'test-app-id';
  const versionName = '1.2.3';
  const versionCode = '1';
  const version = '$versionName+$versionCode';
  const arch = 'aarch64';
  const appDisplayName = 'Test App';
  const channelName = 'stable';
  const platform = 'ios';
  const pubspecYamlContent = '''
name: example
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  assets:
    - shorebird.yaml''';

  const appMetadata = AppMetadata(appId: appId, displayName: appDisplayName);
  const channel = Channel(id: 0, appId: appId, name: channelName);
  const patch = Patch(id: 0, number: 1);
  const patchArtifact = PatchArtifact(
    id: 0,
    patchId: 0,
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
    flutterRevision: flutterRevision,
    displayName: '1.2.3+1',
  );

  group(PatchIosCommand, () {
    late ArgResults argResults;
    late Auth auth;
    late Ipa ipa;
    late IpaReader ipaReader;
    late Progress progress;
    late Logger logger;
    late ShorebirdProcessResult aotBuildProcessResult;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterRevisionProcessResult;
    late http.Client httpClient;
    late CodePushClient codePushClient;
    late Uri? capturedHostedUri;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;

    late PatchIosCommand command;

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

    void setUpTempArtifacts(Directory dir) {
      File(p.join(dir.path, '.dart_tool', 'flutter_build', 'app.dill'))
          .createSync(recursive: true);
      File(p.join(dir.path, 'out.aot')).createSync();
    }

    setUpAll(() {
      registerFallbackValue(_FakeBaseRequest());
      registerFallbackValue(_FakeShorebirdProcess());
    });

    setUp(() {
      argResults = _MockArgResults();
      auth = _MockAuth();
      ipaReader = _MockIpaReader();
      ipa = _MockIpa();
      progress = _MockProgress();
      logger = _MockLogger();
      aotBuildProcessResult = _MockProcessResult();
      flutterBuildProcessResult = _MockProcessResult();
      flutterRevisionProcessResult = _MockProcessResult();
      httpClient = _MockHttpClient();
      codePushClient = _MockCodePushClient();
      flutterValidator = _MockShorebirdFlutterValidator();
      shorebirdProcess = _MockShorebirdProcess();

      command = PatchIosCommand(
        auth: auth,
        ipaReader: ipaReader,
        logger: logger,
        validators: [flutterValidator],
        buildCodePushClient: ({
          required http.Client httpClient,
          Uri? hostedUri,
        }) {
          capturedHostedUri = hostedUri;
          return codePushClient;
        },
      )
        ..testArgResults = argResults
        ..testProcess = shorebirdProcess
        ..testEngineConfig = const EngineConfig.empty();

      when(() => argResults['arch']).thenReturn(arch);
      when(() => argResults['channel']).thenReturn(channelName);
      when(() => argResults['dry-run']).thenReturn(false);
      when(() => argResults['force']).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
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
      when(() => ipa.versionNumber).thenReturn(version);
      when(() => ipaReader.read(any())).thenReturn(ipa);
      when(() => flutterValidator.validate(any())).thenAnswer((_) async => []);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => aotBuildProcessResult.exitCode)
          .thenReturn(ExitCode.success.code);
      when(() => flutterBuildProcessResult.exitCode)
          .thenReturn(ExitCode.success.code);
      when(() => flutterRevisionProcessResult.exitCode)
          .thenReturn(ExitCode.success.code);
      when(
        () => flutterRevisionProcessResult.stdout,
      ).thenReturn(flutterRevision);
      when(
        () => shorebirdProcess.run(
          'git',
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => flutterRevisionProcessResult);
      when(
        () => shorebirdProcess.run(
          'flutter',
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => flutterBuildProcessResult);
      when(
        () => shorebirdProcess.run(
          any(that: endsWith('gen_snapshot_arm64')),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => aotBuildProcessResult);
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
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

    test('exits with code 70 when building fails', () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oops');

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
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.usage.code));
    });

    test('throws error when fetching apps fails.', () async {
      const error = 'something went wrong';
      when(() => codePushClient.getApps()).thenThrow(error);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
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
      setUpTempArtifacts(tempDir);
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
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.success.code);
      verify(() => logger.info('Aborting.')).called(1);
    });

    test('errors when unable to detect flutter revision', () async {
      const error = 'oops';
      when(() => flutterRevisionProcessResult.exitCode).thenReturn(1);
      when(() => flutterRevisionProcessResult.stderr).thenReturn(error);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
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

    test(
        'errors when shorebird flutter revision '
        'does not match release revision', () async {
      const otherRevision = 'other-revision';
      when(() => flutterRevisionProcessResult.stdout).thenReturn(otherRevision);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.software.code);
      final shorebirdFlutterPath = ShorebirdEnvironment.flutterDirectory.path;
      verify(
        () => logger.err('''
Flutter revision mismatch.

The release you are trying to patch was built with a different version of Flutter.

Release Flutter Revision: $flutterRevision
Current Flutter Revision: $otherRevision
'''),
      ).called(1);
      verify(
        () => logger.info('''
Either create a new release using:
  ${lightCyan.wrap('shorebird release')}

Or downgrade your Flutter version and try again using:
  ${lightCyan.wrap('cd $shorebirdFlutterPath')}
  ${lightCyan.wrap('git checkout ${release.flutterRevision}')}

Shorebird plans to support this automatically, let us know if it's important to you:
https://github.com/shorebirdtech/shorebird/issues/472
'''),
      ).called(1);
    });

    test('errors when detecting release version name fails', () async {
      // TODO(bryanoltman): Implement this test.
    });

    test('errors when detecting release version code fails', () async {
      // TODO(bryanoltman): Implement this test.
    });

    test('throws error when fetching releases fails.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenThrow(error);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
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
      setUpTempArtifacts(tempDir);
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

    test('throws error when creating aot snapshot fails', () async {
      const error = 'oops something went wrong';
      when(() => aotBuildProcessResult.exitCode).thenReturn(1);
      when(() => aotBuildProcessResult.stderr).thenReturn(error);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => progress.fail('Exception: Failed to create snapshot: $error'),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('does not create patch on --dry-run', () async {
      when(() => argResults['dry-run']).thenReturn(true);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
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
      setUpTempArtifacts(tempDir);
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
      setUpTempArtifacts(tempDir);
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
      setUpTempArtifacts(tempDir);
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
      setUpTempArtifacts(tempDir);
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
      setUpTempArtifacts(tempDir);
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
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(() => progress.fail(error)).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('succeeds when patch is successful', () async {
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      verify(
        () => logger.info(
          any(
            that: contains(
              '''🕹️  Platform: ${lightCyan.wrap(platform)} ${lightCyan.wrap('[arm64 (0 B)]')}''',
            ),
          ),
        ),
      ).called(1);
      verify(() => logger.success('\n✅ Published Patch!')).called(1);
      expect(exitCode, ExitCode.success.code);
      expect(capturedHostedUri, isNull);
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
      setUpTempArtifacts(tempDir);
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
      setUpTempArtifacts(tempDir);
      const baseUrl = 'https://example.com';
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync(
        '''
app_id: $appId
base_url: $baseUrl''',
      );
      await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(capturedHostedUri, equals(Uri.parse(baseUrl)));
    });

    test('prints flutter validation warnings', () async {
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
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

    test('aborts if validation errors are present', () async {
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      when(() => flutterValidator.validate(any())).thenAnswer(
        (_) async => [
          const ValidationIssue(
            severity: ValidationIssueSeverity.error,
            message: 'There was an issue',
          ),
        ],
      );

      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.config.code));
      verify(() => logger.err('Aborting due to validation errors.')).called(1);
    });
  });
}

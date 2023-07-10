import 'dart:io' hide Platform;

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockIpaReader extends Mock implements IpaReader {}

class _MockIpa extends Mock implements Ipa {}

class _MockLogger extends Mock implements Logger {}

class _MockPlatform extends Mock implements Platform {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockHttpClient extends Mock implements http.Client {}

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
  const platformName = 'ios';
  const elfAotSnapshotFileName = 'out.aot';
  const infoPlistContent = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>app_bundle_name</string>
</dict>
</plist>''';
  const pubspecYamlContent = '''
name: example
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  assets:
    - shorebird.yaml''';

  const appMetadata = AppMetadata(appId: appId, displayName: appDisplayName);
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
    late CodePushClientWrapper codePushClientWrapper;
    late Ipa ipa;
    late IpaReader ipaReader;
    late Progress progress;
    late Logger logger;
    late Platform platform;
    late ShorebirdProcessResult aotBuildProcessResult;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterRevisionProcessResult;
    late http.Client httpClient;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late PatchIosCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
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
      File(
        p.join(tempDir.path, 'ios', 'Runner', 'Info.plist'),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync(infoPlistContent);
      return tempDir;
    }

    void setUpTempArtifacts(Directory dir) {
      // Create a second app.dill for coverage of newestAppDill file.
      File(
        p.join(
          dir.path,
          '.dart_tool',
          'flutter_build',
          'subdir',
          'app.dill',
        ),
      ).createSync(recursive: true);
      File(
        p.join(dir.path, '.dart_tool', 'flutter_build', 'app.dill'),
      ).createSync(recursive: true);
      File(p.join(dir.path, 'build', elfAotSnapshotFileName)).createSync(
        recursive: true,
      );
    }

    setUpAll(() {
      registerFallbackValue(_FakeBaseRequest());
      registerFallbackValue(_FakeShorebirdProcess());
    });

    setUp(() {
      argResults = _MockArgResults();
      auth = _MockAuth();
      codePushClientWrapper = _MockCodePushClientWrapper();
      ipaReader = _MockIpaReader();
      ipa = _MockIpa();
      progress = _MockProgress();
      logger = _MockLogger();
      platform = _MockPlatform();
      aotBuildProcessResult = _MockProcessResult();
      flutterBuildProcessResult = _MockProcessResult();
      flutterRevisionProcessResult = _MockProcessResult();
      httpClient = _MockHttpClient();
      flutterValidator = _MockShorebirdFlutterValidator();
      shorebirdProcess = _MockShorebirdProcess();

      when(() => argResults['arch']).thenReturn(arch);
      when(() => argResults['dry-run']).thenReturn(false);
      when(() => argResults['force']).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
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
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          channelName: any(named: 'channelName'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      ).thenAnswer((_) async {});
      when(() => ipa.versionNumber).thenReturn(version);
      when(() => ipaReader.read(any())).thenReturn(ipa);
      when(() => flutterValidator.validate(any())).thenAnswer((_) async => []);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => platform.environment).thenReturn({});
      when(() => platform.script).thenReturn(
        Uri.file(
          p.join(
            Directory.systemTemp.createTempSync().path,
            'bin',
            'cache',
            'shorebird.snapshot',
          ),
        ),
      );
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

      command = runWithOverrides(
        () => PatchIosCommand(
          ipaReader: ipaReader,
          validators: [flutterValidator],
        ),
      )..testArgResults = argResults;
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    test('is hidden', () {
      expect(command.hidden, isTrue);
    });

    test('throws no user error when user is not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.noUser.code));
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

    test('errors when unable to detect flutter revision', () async {
      const error = 'oops';
      when(() => flutterRevisionProcessResult.exitCode).thenReturn(1);
      when(() => flutterRevisionProcessResult.stderr).thenReturn(error);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
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

    test(
        'errors when shorebird flutter revision '
        'does not match release revision', () async {
      const otherRevision = 'other-revision';
      when(() => flutterRevisionProcessResult.stdout).thenReturn(otherRevision);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.software.code);
      final shorebirdFlutterPath = runWithOverrides(
        () => ShorebirdEnvironment.flutterDirectory.path,
      );
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

    test('exits with code 70 when release version cannot be determiend',
        () async {
      when(() => ipa.versionNumber).thenThrow(Exception('oops'));

      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => progress.fail(
          any(that: contains('Failed to determine release version')),
        ),
      ).called(1);
    });

    test('prints release version when detected', () async {
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.success.code));
      verify(() => progress.complete('Detected release version 1.2.3+1'))
          .called(1);
    });

    test('throws error when creating aot snapshot fails', () async {
      const error = 'oops something went wrong';
      when(() => aotBuildProcessResult.exitCode).thenReturn(1);
      when(() => aotBuildProcessResult.stderr).thenReturn(error);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
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
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(
        () => codePushClientWrapper.createPatch(
          releaseId: any(named: 'releaseId'),
        ),
      );
      verify(() => logger.info('No issues detected.')).called(1);
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
      verify(
        () => logger.info(
          any(
            that: contains(
              '''🕹️  Platform: ${lightCyan.wrap(platformName)} ${lightCyan.wrap('[aarch64 (0 B)]')}''',
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
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verify(() => logger.success('\n✅ Published Patch!')).called(1);
      expect(exitCode, ExitCode.success.code);
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
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
    });

    test('provides appropriate ExportOptions.plist to build ipa command',
        () async {
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
      final capturedArgs = verify(
        () => shorebirdProcess.run(
          'flutter',
          captureAny(),
          runInShell: any(named: 'runInShell'),
        ),
      ).captured.first as List<String>;
      final exportOptionsPlistFile = File(
        capturedArgs
            .whereType<String>()
            .firstWhere((arg) => arg.contains('export-options-plist'))
            .split('=')
            .last,
      );
      expect(exportOptionsPlistFile.existsSync(), isTrue);
      final exportOptionsPlist =
          PropertyListSerialization.propertyListWithString(
        exportOptionsPlistFile.readAsStringSync(),
      ) as Map<String, Object>;
      expect(exportOptionsPlist['manageAppVersionAndBuildNumber'], isFalse);
      expect(exportOptionsPlist['signingStyle'], 'automatic');
      expect(exportOptionsPlist['uploadBitcode'], isFalse);
      expect(exportOptionsPlist['method'], 'app-store');
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
        () => runWithOverrides(command.run),
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
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.config.code));
      verify(() => logger.err('Aborting due to validation errors.')).called(1);
    });
  });
}

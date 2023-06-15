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
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockIpa extends Mock implements Ipa {}

class _MockIpaReader extends Mock implements IpaReader {}

class _MockLogger extends Mock implements Logger {}

class _MockPlatform extends Mock implements Platform {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group(ReleaseIosCommand, () {
    const appId = 'test-app-id';
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const versionName = '1.2.3';
    const versionCode = '1';
    const version = '$versionName+$versionCode';
    const appDisplayName = 'Test App';
    const arch = 'armv7';
    const platform = 'ios';
    const appMetadata = AppMetadata(appId: appId, displayName: appDisplayName);
    const release = Release(
      id: 0,
      appId: appId,
      version: version,
      flutterRevision: flutterRevision,
      displayName: '1.2.3+1',
    );

    const pubspecYamlContent = '''
name: example
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  assets:
    - shorebird.yaml''';

    late ArgResults argResults;
    late http.Client httpClient;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory shorebirdRoot;
    late Platform environmentPlatform;
    late Auth auth;
    late IpaReader ipaReader;
    late Ipa ipa;
    late Progress progress;
    late Logger logger;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterRevisionProcessResult;
    late ReleaseIosCommand command;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => environmentPlatform),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
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

    setUp(() {
      argResults = _MockArgResults();
      codePushClientWrapper = _MockCodePushClientWrapper();
      httpClient = _MockHttpClient();
      environmentPlatform = _MockPlatform();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      auth = _MockAuth();
      ipa = _MockIpa();
      ipaReader = _MockIpaReader();
      progress = _MockProgress();
      logger = _MockLogger();
      flutterBuildProcessResult = _MockProcessResult();
      flutterRevisionProcessResult = _MockProcessResult();
      flutterValidator = _MockShorebirdFlutterValidator();
      shorebirdProcess = _MockShorebirdProcess();

      registerFallbackValue(shorebirdProcess);

      when(() => environmentPlatform.script).thenReturn(
        Uri.file(
          p.join(
            shorebirdRoot.path,
            'bin',
            'cache',
            'shorebird.snapshot',
          ),
        ),
      );
      when(
        () => shorebirdProcess.run(
          'flutter',
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => flutterBuildProcessResult);
      when(
        () => shorebirdProcess.run(
          'git',
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => flutterRevisionProcessResult);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['arch']).thenReturn(arch);
      when(() => argResults['platform']).thenReturn(platform);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(() => ipaReader.read(any())).thenReturn(ipa);
      when(() => ipa.versionNumber).thenReturn(version);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.confirm(any())).thenReturn(true);
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(version);
      when(
        () => flutterBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => flutterRevisionProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => flutterRevisionProcessResult.stdout,
      ).thenReturn(flutterRevision);
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
        () => codePushClientWrapper.createRelease(
          appId: any(named: 'appId'),
          version: any(named: 'version'),
          flutterRevision: any(named: 'flutterRevision'),
        ),
      ).thenAnswer((_) async => release);
      when(() => flutterValidator.validate(any())).thenAnswer((_) async => []);

      command = runWithOverrides(
        () => ReleaseIosCommand(
          ipaReader: ipaReader,
          validators: [flutterValidator],
        ),
      )
        ..testArgResults = argResults
        ..testProcess = shorebirdProcess
        ..testEngineConfig = const EngineConfig.empty();
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    test('is hidden', () {
      expect(command.hidden, isTrue);
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

    test('throws no user error when user is not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.noUser.code));
    });

    test('exits with code 70 when build fails with non-zero exit code',
        () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oops');

      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => progress.fail(any(that: contains('Failed to build'))),
      ).called(1);
    });

    test('exits with code 70 when building fails with 0 exit code', () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(0);
      when(() => flutterBuildProcessResult.stderr).thenReturn('''
Encountered error while creating the IPA:
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found
error: exportArchive: Team "My Team" does not have permission to create "iOS App Store" provisioning profiles.
error: exportArchive: No profiles for 'com.example.co' were found
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found
error: exportArchive: Communication with Apple failed
error: exportArchive: No signing certificate "iOS Distribution" found
''');

      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => progress.fail(any(that: contains('Failed to build'))),
      ).called(1);
      verify(
        () => logger.err('''
    Communication with Apple failed
    No signing certificate "iOS Distribution" found
    Team "My Team" does not have permission to create "iOS App Store" provisioning profiles.
    No profiles for 'com.example.co' were found'''),
      ).called(1);
    });

    test('exits with code 70 when release version cannot be determiend',
        () async {
      when(() => ipa.versionNumber).thenThrow(Exception('oops'));

      final tempDir = setUpTempDir();
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

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
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
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.config.code));
      verify(() => logger.err('Aborting due to validation errors.')).called(1);
    });

    test('aborts when user opts out', () async {
      when(() => logger.confirm(any())).thenReturn(false);
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

    test('throws error when existing releases exists.', () async {
      when(
        () => codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
      final tempDir = setUpTempDir();

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      verify(
        () => logger.err('''
It looks like you have an existing release for version ${lightCyan.wrap(release.version)}.
Please bump your version number and try again.'''),
      ).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test(
        'does not prompt for confirmation '
        'when --release-version and --force are used', () async {
      when(() => argResults['force']).thenReturn(true);
      when(() => argResults['release-version']).thenReturn(version);
      final tempDir = setUpTempDir();

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      verify(() => logger.success('\n✅ Published Release!')).called(1);
      expect(exitCode, ExitCode.success.code);
      verifyNever(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      );
    });

    test('succeeds when release is successful', () async {
      final tempDir = setUpTempDir();

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      verify(() => logger.success('\n✅ Published Release!')).called(1);
      verify(
        () => logger.info(
          any(
            that: stringContainsInOrder(
              [
                'Your next step is to upload the ipa to App Store Connect.',
                'build/ios/ipa/example.ipa',
              ],
            ),
          ),
        ),
      ).called(1);
      expect(exitCode, ExitCode.success.code);
    });

    test(
        'succeeds when release is successful '
        'with flavors and target', () async {
      const flavor = 'development';
      final target = p.join('lib', 'main_development.dart');
      when(() => argResults['flavor']).thenReturn(flavor);
      when(() => argResults['target']).thenReturn(target);
      final tempDir = setUpTempDir();
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

      verify(() => logger.success('\n✅ Published Release!')).called(1);
      verify(
        () => logger.info(
          any(
            that: stringContainsInOrder(
              [
                'Your next step is to upload the ipa to App Store Connect.',
                'build/ios/ipa/example.ipa',
              ],
            ),
          ),
        ),
      ).called(1);
      expect(exitCode, ExitCode.success.code);
    });

    test('provides appropriate ExportOptions.plist to build ipa command',
        () async {
      final tempDir = setUpTempDir();

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
  });
}

import 'dart:io' hide Platform;

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockLogger extends Mock implements Logger {}

class _MockPlatform extends Mock implements Platform {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockCodePushClient extends Mock implements CodePushClient {}

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

    const releaseXcConfigContent = '#include "Generated.xcconfig"';
    const generatedXcConfigContent = '''
// This is a generated file; do not edit or check into version control.
FLUTTER_TARGET=lib/main.dart
FLUTTER_BUILD_DIR=build
FLUTTER_BUILD_NAME=1.2.3
FLUTTER_BUILD_NUMBER=1
''';
    const nonParameterizedInfoPlistContent = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1.0.0</string>
</dict>
</plist>
''';
    const parameterizedInfoPlistContent = r'''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleShortVersionString</key>
	<string>$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
</dict>
</plist>
''';

    late ArgResults argResults;
    late http.Client httpClient;
    late Directory shorebirdRoot;
    late Platform environmentPlatform;
    late Auth auth;
    late Progress progress;
    late Logger logger;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterRevisionProcessResult;
    late CodePushClient codePushClient;
    late ReleaseIosCommand command;
    late Uri? capturedHostedUri;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;

    Directory setUpTempDir({
      bool useParameterizedInfoPlist = true,
      bool includeConfigContent = true,
      bool includePlist = true,
    }) {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('app_id: $appId');

      final releaseConfigFile =
          File(p.join(tempDir.path, 'ios', 'Flutter', 'Release.xcconfig'))
            ..createSync(recursive: true);
      final generatedConfigFile =
          File(p.join(tempDir.path, 'ios', 'Flutter', 'Generated.xcconfig'))
            ..createSync(recursive: true);
      if (includeConfigContent) {
        generatedConfigFile.writeAsStringSync(generatedXcConfigContent);
        releaseConfigFile.writeAsStringSync(releaseXcConfigContent);
      } else {
        // generatedConfigFile.writeAsStringSync('');
        // releaseConfigFile.writeAsStringSync('');
      }

      if (includePlist) {
        if (useParameterizedInfoPlist) {
          (File(p.join(tempDir.path, 'ios', 'Runner', 'Info.plist'))
                ..createSync(recursive: true))
              .writeAsStringSync(parameterizedInfoPlistContent);
        } else {
          (File(p.join(tempDir.path, 'ios', 'Runner', 'Info.plist'))
                ..createSync(recursive: true))
              .writeAsStringSync(nonParameterizedInfoPlistContent);
        }
      }

      return tempDir;
    }

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      environmentPlatform = _MockPlatform();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      auth = _MockAuth();
      progress = _MockProgress();
      logger = _MockLogger();
      flutterBuildProcessResult = _MockProcessResult();
      flutterRevisionProcessResult = _MockProcessResult();
      codePushClient = _MockCodePushClient();
      flutterValidator = _MockShorebirdFlutterValidator();
      shorebirdProcess = _MockShorebirdProcess();
      command = ReleaseIosCommand(
        auth: auth,
        buildCodePushClient: ({
          required http.Client httpClient,
          Uri? hostedUri,
        }) {
          capturedHostedUri = hostedUri;
          return codePushClient;
        },
        logger: logger,
        validators: [flutterValidator],
      )
        ..testArgResults = argResults
        ..testProcess = shorebirdProcess
        ..testEngineConfig = const EngineConfig.empty();

      registerFallbackValue(shorebirdProcess);

      ShorebirdEnvironment.platform = environmentPlatform;
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
        () => codePushClient.getApps(),
      ).thenAnswer((_) async => [appMetadata]);
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      when(
        () => codePushClient.createRelease(
          appId: any(named: 'appId'),
          version: any(named: 'version'),
          flutterRevision: any(named: 'flutterRevision'),
        ),
      ).thenAnswer((_) async => release);
      when(() => flutterValidator.validate(any())).thenAnswer((_) async => []);
    });

    test('has a description', () {
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

    test('throws no user error when user is not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => command.run(),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.noUser.code));
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

    group('release version', () {
      test('throws error if plist cannot be found', () async {
        final tempDir = setUpTempDir(includePlist: false);

        final exitCode = await IOOverrides.runZoned(
          command.run,
          getCurrentDirectory: () => tempDir,
        );

        expect(exitCode, ExitCode.software.code);
        verify(() => logger.err(any())).called(1);
      });

      test(
          '''throws error if plist contains variables and config fails do not contain those variables''',
          () async {
        final tempDir = setUpTempDir(includeConfigContent: false);

        final exitCode = await IOOverrides.runZoned(
          command.run,
          getCurrentDirectory: () => tempDir,
        );

        expect(exitCode, ExitCode.software.code);
        verify(() => logger.err(any())).called(1);
      });

      test(
          """looks up variables in config files if plist doesn't contain raw version number""",
          () async {
        final tempDir = setUpTempDir(
          includeConfigContent: false,
          useParameterizedInfoPlist: false,
        );

        final exitCode = await IOOverrides.runZoned(
          command.run,
          getCurrentDirectory: () => tempDir,
        );

        expect(exitCode, ExitCode.success.code);
        verifyNever(() => logger.err(any()));
        verify(
          () =>
              logger.info(any(that: contains('Release Version: 1.0.0+1.0.0'))),
        ).called(1);
      });

      test('determines app version from plist and xcconfig files', () async {
        final tempDir = setUpTempDir();

        final exitCode = await IOOverrides.runZoned(
          command.run,
          getCurrentDirectory: () => tempDir,
        );

        expect(exitCode, ExitCode.success.code);
        verifyNever(() => logger.err(any()));
        verify(
          () => logger.info(any(that: contains('Release Version: 1.2.3+1'))),
        ).called(1);
      });
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
        command.run,
        getCurrentDirectory: () => tempDir,
      );

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
      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, equals(ExitCode.config.code));
      verify(() => logger.err('Aborting due to validation errors.')).called(1);
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
      final tempDir = setUpTempDir();

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

    test('throws error when existing releases exists.', () async {
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenAnswer((_) async => [release]);
      final tempDir = setUpTempDir();

      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );

      verify(() => logger.err('''
It looks like you have an existing release for version ${lightCyan.wrap(release.version)}.
Please bump your version number and try again.''')).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test('throws error when creating release fails.', () async {
      const error = 'something went wrong';
      when(
        () => codePushClient.createRelease(
          appId: any(named: 'appId'),
          version: any(named: 'version'),
          flutterRevision: any(named: 'flutterRevision'),
          displayName: any(named: 'displayName'),
        ),
      ).thenThrow(error);
      final tempDir = setUpTempDir();

      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );

      verify(() => progress.fail(error)).called(1);
      expect(exitCode, ExitCode.software.code);
    });

    test(
        'does not prompt for confirmation '
        'when --release-version and --force are used', () async {
      when(() => argResults['force']).thenReturn(true);
      when(() => argResults['release-version']).thenReturn(version);
      final tempDir = setUpTempDir();

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

      final exitCode = await IOOverrides.runZoned(
        command.run,
        getCurrentDirectory: () => tempDir,
      );

      verify(() => logger.success('\n✅ Published Release!')).called(1);
      expect(exitCode, ExitCode.success.code);
      expect(capturedHostedUri, isNull);
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
        command.run,
        getCurrentDirectory: () => tempDir,
      );

      verify(() => logger.success('\n✅ Published Release!')).called(1);
      expect(exitCode, ExitCode.success.code);
      expect(capturedHostedUri, isNull);
    });
  });
}

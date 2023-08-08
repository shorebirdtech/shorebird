import 'dart:io' hide Platform;

import 'package:args/args.dart';
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
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockDoctor extends Mock implements Doctor {}

class _MockIpa extends Mock implements Ipa {}

class _MockIpaReader extends Mock implements IpaReader {}

class _MockLogger extends Mock implements Logger {}

class _MockPlatform extends Mock implements Platform {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

class _FakeRelease extends Fake implements Release {}

class _FakeShorebirdProcess extends Fake implements ShorebirdProcess {}

void main() {
  group(ReleaseIosCommand, () {
    const appId = 'test-app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const versionName = '1.2.3';
    const versionCode = '1';
    const version = '$versionName+$versionCode';
    const appDisplayName = 'Test App';
    const arch = 'armv7';
    const releasePlatform = ReleasePlatform.ios;
    const ipaPath = 'build/ios/ipa/Runner.ipa';
    const appMetadata = AppMetadata(appId: appId, displayName: appDisplayName);
    const release = Release(
      id: 0,
      appId: appId,
      version: version,
      flutterRevision: flutterRevision,
      displayName: '1.2.3+1',
      platformStatuses: {},
    );
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

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory shorebirdRoot;
    late Doctor doctor;
    late Platform platform;
    late Auth auth;
    late IpaReader ipaReader;
    late Ipa ipa;
    late Progress progress;
    late Logger logger;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ReleaseIosCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
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
      File(p.join(tempDir.path, ipaPath)).createSync(recursive: true);
      return tempDir;
    }

    setUpAll(() {
      registerFallbackValue(ReleasePlatform.ios);
      registerFallbackValue(ReleaseStatus.draft);
      registerFallbackValue(_FakeRelease());
      registerFallbackValue(_FakeShorebirdProcess());
    });

    setUp(() {
      argResults = _MockArgResults();
      codePushClientWrapper = _MockCodePushClientWrapper();
      doctor = _MockDoctor();
      platform = _MockPlatform();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      auth = _MockAuth();
      ipa = _MockIpa();
      ipaReader = _MockIpaReader();
      progress = _MockProgress();
      logger = _MockLogger();
      flutterBuildProcessResult = _MockProcessResult();
      flutterValidator = _MockShorebirdFlutterValidator();
      shorebirdProcess = _MockShorebirdProcess();
      shorebirdEnv = _MockShorebirdEnv();
      shorebirdValidator = _MockShorebirdValidator();

      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(
        () => shorebirdProcess.run(
          'flutter',
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => flutterBuildProcessResult);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['arch']).thenReturn(arch);
      when(() => argResults['platform']).thenReturn(releasePlatform);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => ipaReader.read(any())).thenReturn(ipa);
      when(() => ipa.versionNumber).thenReturn(version);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.confirm(any())).thenReturn(true);
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(version);
      when(() => platform.operatingSystem).thenReturn(Platform.macOS);
      when(
        () => flutterBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
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
        () => codePushClientWrapper.createIosReleaseArtifacts(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          ipaPath: any(named: 'ipaPath'),
          runnerPath: any(named: 'runnerPath'),
        ),
      ).thenAnswer((_) async => release);
      when(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          status: any(named: 'status'),
        ),
      ).thenAnswer((_) async => {});

      when(() => doctor.iosCommandValidators).thenReturn([flutterValidator]);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
          supportedOperatingSystems: any(named: 'supportedOperatingSystems'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(() => ReleaseIosCommand(ipaReader: ipaReader))
        ..testArgResults = argResults;
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    test('exits when validation fails', () async {
      final exception = ValidationFailedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
          supportedOperatingSystems: any(named: 'supportedOperatingSystems'),
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
          validators: [flutterValidator],
          supportedOperatingSystems: {Platform.macOS},
        ),
      ).called(1);
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

    test('aborts when user opts out', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      final tempDir = setUpTempDir();

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
      verify(() => logger.info('Aborting.')).called(1);
      verifyNever(
        () => codePushClientWrapper.createIosReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          ipaPath: any(named: 'ipaPath', that: endsWith('.ipa')),
          runnerPath: any(named: 'runnerPath', that: endsWith('Runner.app')),
        ),
      );
    });

    test('exits with code 70 if build directory does not exist', () async {
      final tempDir = setUpTempDir();
      Directory(p.join(tempDir.path, 'build')).deleteSync(recursive: true);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => progress.fail(
          any(
            that: stringContainsInOrder([
              'Could not find ipa file',
              'No directory found at ${p.join(tempDir.path, 'build')}',
            ]),
          ),
        ),
      ).called(1);
    });

    test('exits with code 70 if ipa file does not exist', () async {
      final tempDir = setUpTempDir();
      File(p.join(tempDir.path, ipaPath)).deleteSync(recursive: true);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => progress.fail(
          any(
            that: stringContainsInOrder([
              'Could not find ipa file',
              'No .ipa files found in',
              p.join('build', 'ios', 'ipa'),
            ]),
          ),
        ),
      ).called(1);
    });

    test('exits with code 70 if more than one ipa file is found', () async {
      final tempDir = setUpTempDir();
      File(p.join(tempDir.path, 'build/ios/ipa/Runner2.ipa'))
          .createSync(recursive: true);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => progress.fail(
          any(
            that: stringContainsInOrder([
              'Could not find ipa file',
              'More than one .ipa file found in',
              p.join('build', 'ios', 'ipa'),
            ]),
          ),
        ),
      ).called(1);
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
      verify(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          status: ReleaseStatus.active,
        ),
      ).called(1);
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
                p.join('build', 'ios', 'ipa', 'Runner.ipa'),
              ],
            ),
          ),
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.createIosReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          ipaPath: any(named: 'ipaPath', that: endsWith('.ipa')),
          runnerPath: any(named: 'runnerPath', that: endsWith('Runner.app')),
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
                p.join('build', 'ios', 'ipa', 'Runner.ipa'),
              ],
            ),
          ),
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.createIosReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          ipaPath: any(named: 'ipaPath', that: endsWith('.ipa')),
          runnerPath: any(named: 'runnerPath', that: endsWith('Runner.app')),
        ),
      ).called(1);
      expect(exitCode, ExitCode.success.code);
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
        () => codePushClientWrapper.createIosReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          ipaPath: any(named: 'ipaPath', that: endsWith('.ipa')),
          runnerPath: any(named: 'runnerPath', that: endsWith('Runner.app')),
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

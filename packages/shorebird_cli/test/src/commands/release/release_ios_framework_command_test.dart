import 'dart:io' hide Platform;

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/release.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockDoctor extends Mock implements Doctor {}

class _MockLogger extends Mock implements Logger {}

class _MockPlatform extends Mock implements Platform {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group(ReleaseIosFrameworkCommand, () {
    const appId = 'test-app-id';
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const versionName = '1.2.3';
    const versionCode = '1';
    const version = '$versionName+$versionCode';
    const appDisplayName = 'Test App';
    const releasePlatform = ReleasePlatform.ios;
    const appMetadata = AppMetadata(appId: appId, displayName: appDisplayName);
    const release = Release(
      id: 0,
      appId: appId,
      version: version,
      flutterRevision: flutterRevision,
      displayName: '1.2.3+1',
      platformStatuses: {},
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
    late CodePushClientWrapper codePushClientWrapper;
    late Directory shorebirdRoot;
    late Doctor doctor;
    late Platform platform;
    late Auth auth;
    late Progress progress;
    late Logger logger;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterRevisionProcessResult;
    late ReleaseIosFrameworkCommand command;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;

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

    setUpAll(() {
      registerFallbackValue(ReleasePlatform.ios);
      registerFallbackValue(ReleaseStatus.draft);
    });

    setUp(() {
      argResults = _MockArgResults();
      codePushClientWrapper = _MockCodePushClientWrapper();
      doctor = _MockDoctor();
      platform = _MockPlatform();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      auth = _MockAuth();
      progress = _MockProgress();
      logger = _MockLogger();
      flutterBuildProcessResult = _MockProcessResult();
      flutterRevisionProcessResult = _MockProcessResult();
      flutterValidator = _MockShorebirdFlutterValidator();
      shorebirdProcess = _MockShorebirdProcess();

      registerFallbackValue(release);
      registerFallbackValue(shorebirdProcess);

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
      when(() => argResults['release-version']).thenReturn(version);
      when(() => argResults['force']).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => doctor.iosCommandValidators).thenReturn([flutterValidator]);
      when(
        () => flutterBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => flutterRevisionProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => flutterRevisionProcessResult.stdout,
      ).thenReturn(flutterRevision);
      when(flutterValidator.validate).thenAnswer((_) async => []);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => platform.operatingSystem).thenReturn(Platform.macOS);
      when(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
      ).thenAnswer((_) async => appMetadata);
      when(
        () => codePushClientWrapper.createIosFrameworkReleaseArtifacts(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          appFrameworkPath: any(named: 'appFrameworkPath'),
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
        () => codePushClientWrapper.updateReleaseStatus(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          status: any(named: 'status'),
        ),
      ).thenAnswer((_) async => {});

      command = runWithOverrides(ReleaseIosFrameworkCommand.new)
        ..testArgResults = argResults;
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    test('exits with unavailable code if run on non-macOS platform', () async {
      when(() => platform.operatingSystem).thenReturn(Platform.windows);

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.unavailable.code));
      verify(() => logger.err('This command is only supported on macos.'))
          .called(1);
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
    });

    test('checks that release is not active if release exists', () async {
      when(
        () => codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
      final tempDir = setUpTempDir();

      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      verify(
        () => codePushClientWrapper.ensureReleaseIsNotActive(
          release: release,
          platform: releasePlatform,
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
                'Your next step is to include the .xcframework files in',
                '/build/ios/framework/Release',
                'in your iOS app.'
              ],
            ),
          ),
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.createIosFrameworkReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          appFrameworkPath: any(
            named: 'appFrameworkPath',
            that: endsWith('build/ios/framework/Release/App.xcframework'),
          ),
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
      final arguments = [
        'build',
        'ios-framework',
        '--no-debug',
        '--no-profile',
        '--flavor=$flavor',
        '--target=$target',
      ];
      verify(
        () => shorebirdProcess.run('flutter', arguments, runInShell: true),
      ).called(1);
      verify(
        () => logger.info(
          any(that: contains('🍧 Flavor: ${lightCyan.wrap(flavor)}')),
        ),
      ).called(1);
      verify(() => logger.success('\n✅ Published Release!')).called(1);
      verify(
        () => logger.info(
          any(
            that: stringContainsInOrder(
              [
                'Your next step is to include the .xcframework files in',
                '/build/ios/framework/Release',
                'in your iOS app.'
              ],
            ),
          ),
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.createIosFrameworkReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          appFrameworkPath: any(
            named: 'appFrameworkPath',
            that: endsWith('build/ios/framework/Release/App.xcframework'),
          ),
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
  });
}

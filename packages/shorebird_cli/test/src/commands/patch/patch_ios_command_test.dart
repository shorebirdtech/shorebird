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
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockDoctor extends Mock implements Doctor {}

class _MockIpaDiffer extends Mock implements IosArchiveDiffer {}

class _MockLogger extends Mock implements Logger {}

class _MockPatchDiffChecker extends Mock implements PatchDiffChecker {}

class _MockPlatform extends Mock implements Platform {}

class _MockProgress extends Mock implements Progress {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

class _MockShorebirdFlutter extends Mock implements ShorebirdFlutter {}

class _MockShorebirdFlutterValidator extends Mock
    implements ShorebirdFlutterValidator {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

class _FakeShorebirdProcess extends Fake implements ShorebirdProcess {}

void main() {
  const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
  const appId = 'test-app-id';
  const shorebirdYaml = ShorebirdYaml(appId: appId);
  const versionName = '1.2.3';
  const versionCode = '1';
  const version = '$versionName+$versionCode';
  const arch = 'aarch64';
  const appDisplayName = 'Test App';
  const platformName = 'ios';
  const elfAotSnapshotFileName = 'out.aot';
  const ipaPath = 'build/ios/ipa/Runner.ipa';
  const infoPlistContent = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ApplicationProperties</key>
	<dict>
		<key>ApplicationPath</key>
		<string>Applications/Runner.app</string>
		<key>Architectures</key>
		<array>
			<string>arm64</string>
		</array>
		<key>CFBundleIdentifier</key>
		<string>com.shorebird.timeShift</string>
		<key>CFBundleShortVersionString</key>
		<string>1.2.3</string>
		<key>CFBundleVersion</key>
		<string>1</string>
	</dict>
	<key>ArchiveVersion</key>
	<integer>2</integer>
	<key>Name</key>
	<string>Runner</string>
	<key>SchemeName</key>
	<string>Runner</string>
</dict>
</plist>''';
  const emptyPlistContent = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ApplicationProperties</key>
	<dict>
	</dict>
</dict>
</plist>'
''';
  const pubspecYamlContent = '''
name: example
version: $version
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  assets:
    - shorebird.yaml''';

  const appMetadata = AppMetadata(appId: appId, displayName: appDisplayName);
  const ipaArtifact = ReleaseArtifact(
    id: 0,
    releaseId: 0,
    arch: arch,
    platform: ReleasePlatform.ios,
    hash: '#',
    size: 42,
    url: 'https://example.com/release.ipa',
  );
  const release = Release(
    id: 0,
    appId: appId,
    version: version,
    flutterRevision: flutterRevision,
    displayName: '1.2.3+1',
    platformStatuses: {ReleasePlatform.ios: ReleaseStatus.active},
  );

  group(PatchIosCommand, () {
    late ArgResults argResults;
    late Auth auth;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory flutterDirectory;
    late Directory shorebirdRoot;
    late File genSnapshotFile;
    late Doctor doctor;
    late IosArchiveDiffer archiveDiffer;
    late Progress progress;
    late Logger logger;
    late PatchDiffChecker patchDiffChecker;
    late Platform platform;
    late ShorebirdProcessResult aotBuildProcessResult;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterPubGetProcessResult;
    late http.Client httpClient;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdValidator shorebirdValidator;
    late PatchIosCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          loggerRef.overrideWith(() => logger),
          patchDiffCheckerRef.overrideWith(() => patchDiffChecker),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
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
        p.join(
          tempDir.path,
          'build',
          'ios',
          'archive',
          'Runner.xcarchive',
          'Info.plist',
        ),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync(infoPlistContent);
      File(p.join(tempDir.path, ipaPath)).createSync(recursive: true);
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
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(FileSetDiff.empty());
      registerFallbackValue(ReleasePlatform.ios);
      registerFallbackValue(Uri.parse('https://example.com'));
      registerFallbackValue(_FakeBaseRequest());
      registerFallbackValue(_FakeShorebirdProcess());
    });

    setUp(() {
      argResults = _MockArgResults();
      auth = _MockAuth();
      codePushClientWrapper = _MockCodePushClientWrapper();
      doctor = _MockDoctor();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      flutterDirectory = Directory(
        p.join(shorebirdRoot.path, 'bin', 'cache', 'flutter'),
      );
      genSnapshotFile = File(
        p.join(
          flutterDirectory.path,
          'bin',
          'cache',
          'artifacts',
          'engine',
          'ios-release',
          'gen_snapshot_arm64',
        ),
      );
      archiveDiffer = _MockIpaDiffer();
      progress = _MockProgress();
      logger = _MockLogger();
      platform = _MockPlatform();
      aotBuildProcessResult = _MockProcessResult();
      flutterBuildProcessResult = _MockProcessResult();
      flutterPubGetProcessResult = _MockProcessResult();
      httpClient = _MockHttpClient();
      patchDiffChecker = _MockPatchDiffChecker();
      shorebirdEnv = _MockShorebirdEnv();
      shorebirdFlutter = _MockShorebirdFlutter();
      flutterValidator = _MockShorebirdFlutterValidator();
      shorebirdProcess = _MockShorebirdProcess();
      shorebirdValidator = _MockShorebirdValidator();

      when(() => argResults['arch']).thenReturn(arch);
      when(() => argResults['dry-run']).thenReturn(false);
      when(() => argResults['force']).thenReturn(false);
      when(() => argResults['release-version']).thenReturn(release.version);
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
        () => codePushClientWrapper.getReleaseArtifact(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async => ipaArtifact);
      when(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          channelName: any(named: 'channelName'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      ).thenAnswer((_) async {});
      when(() => doctor.iosCommandValidators).thenReturn([flutterValidator]);
      when(flutterValidator.validate).thenAnswer((_) async => []);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => platform.operatingSystem).thenReturn(Platform.macOS);
      when(() => platform.environment).thenReturn({});
      when(() => platform.script).thenReturn(shorebirdRoot.uri);
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(() => shorebirdEnv.genSnapshotFile).thenReturn(genSnapshotFile);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(() => shorebirdEnv.isRunningOnCI).thenReturn(false);
      when(() => shorebirdFlutter.useRevision(revision: any(named: 'revision')))
          .thenAnswer((_) async {});
      when(
        () => aotBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => flutterBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(() => flutterPubGetProcessResult.exitCode)
          .thenReturn(ExitCode.success.code);
      when(
        () => shorebirdProcess.run(
          'flutter',
          ['--no-version-check', 'pub', 'get', '--offline'],
          runInShell: any(named: 'runInShell'),
          useVendedFlutter: false,
        ),
      ).thenAnswer((_) async => flutterPubGetProcessResult);
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
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
          supportedOperatingSystems: any(named: 'supportedOperatingSystems'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifactUrl: any(named: 'releaseArtifactUrl'),
          archiveDiffer: archiveDiffer,
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async => {});

      command = runWithOverrides(
        () => PatchIosCommand(archiveDiffer: archiveDiffer),
      )..testArgResults = argResults;
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

    test('exits with code 70 when building fails (due to BuildException)',
        () async {
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

    test('exits with code 70 if build directory does not exist', () async {
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      Directory(p.join(tempDir.path, 'build')).deleteSync(recursive: true);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => logger.err(any(that: contains('No Info.plist file found'))),
      ).called(1);
    });

    test(
        '''exits with code 70 if release does not exist for the ios platform''',
        () async {
      when(
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer(
        (_) async => const Release(
          id: 0,
          appId: appId,
          version: version,
          flutterRevision: flutterRevision,
          displayName: '1.2.3+1',
          platformStatuses: {ReleasePlatform.android: ReleaseStatus.active},
        ),
      );
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.software.code);
      verify(() => logger.err('No iOS release found for 1.2.3+1.')).called(1);
    });

    test(
        '''exits with code 70 if release is in draft state for the ios platform''',
        () async {
      when(
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer(
        (_) async => const Release(
          id: 0,
          appId: appId,
          version: version,
          flutterRevision: flutterRevision,
          displayName: '1.2.3+1',
          platformStatuses: {ReleasePlatform.ios: ReleaseStatus.draft},
        ),
      );
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.software.code);
      verify(
        () => logger.err('''
Release 1.2.3+1 is in an incomplete state. It's possible that the original release was terminated or failed to complete.
Please re-run the release command for this version or create a new release.'''),
      ).called(1);
    });

    test('proceeds if release is in draft state for a non-ios platform',
        () async {
      when(
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer(
        (_) async => const Release(
          id: 0,
          appId: appId,
          version: version,
          flutterRevision: flutterRevision,
          displayName: '1.2.3+1',
          platformStatuses: {
            ReleasePlatform.android: ReleaseStatus.draft,
            ReleasePlatform.ios: ReleaseStatus.active,
          },
        ),
      );
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(exitCode, ExitCode.success.code);
    });

    test(
        '''switches to release flutter revision when shorebird flutter revision does not match''',
        () async {
      const otherRevision = 'other-revision';
      when(() => shorebirdEnv.flutterRevision).thenReturn(otherRevision);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
      // Verify that we switch back to the original revision once we're done.
      verifyInOrder([
        () => shorebirdFlutter.useRevision(revision: release.flutterRevision),
        () => shorebirdFlutter.useRevision(revision: otherRevision),
      ]);

      verify(
        () => logger.info(
          any(
            that: stringContainsInOrder([
              '''The release you are trying to patch was built with a different version of Flutter.''',
              'Release Flutter Revision: ${release.flutterRevision}',
              'Current Flutter Revision: $otherRevision',
            ]),
          ),
        ),
      ).called(1);
    });

    test(
      'exits with code 70 if build fails after switching flutter versions',
      () async {
        const otherRevision = 'other-revision';
        when(() => shorebirdEnv.flutterRevision).thenReturn(otherRevision);
        when(
          () => shorebirdFlutter.useRevision(revision: any(named: 'revision')),
        ).thenAnswer((invocation) async {
          // Cause builds to fail after switching flutter versions.
          when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
          when(() => flutterBuildProcessResult.stderr).thenReturn('oops');
        });
        final tempDir = setUpTempDir();
        setUpTempArtifacts(tempDir);

        final exitCode = await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );

        expect(exitCode, equals(ExitCode.software.code));
      },
    );

    test('exits with code 70 when release version cannot be determiend',
        () async {
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      File(
        p.join(
          tempDir.path,
          'build',
          'ios',
          'archive',
          'Runner.xcarchive',
          'Info.plist',
        ),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync(emptyPlistContent);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => logger.err(
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
      verify(() => logger.info('Detected release version 1.2.3+1')).called(1);
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

    test(
        '''exits with code 0 if zipAndConfirmUnpatchableDiffsIfNecessary throws UserCancelledException''',
        () async {
      when(() => argResults['force']).thenReturn(false);
      when(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifactUrl: any(named: 'releaseArtifactUrl'),
          archiveDiffer: archiveDiffer,
          force: any(named: 'force'),
        ),
      ).thenThrow(UserCancelledException());
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifactUrl: Uri.parse(ipaArtifact.url),
          archiveDiffer: archiveDiffer,
          force: false,
        ),
      ).called(1);
      verifyNever(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          channelName: any(named: 'channelName'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      );
    });

    test(
        '''exits with code 70 if zipAndConfirmUnpatchableDiffsIfNecessary throws UnpatchableChangeException''',
        () async {
      when(() => argResults['force']).thenReturn(false);
      when(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifactUrl: any(named: 'releaseArtifactUrl'),
          archiveDiffer: archiveDiffer,
          force: any(named: 'force'),
        ),
      ).thenThrow(UnpatchableChangeException());
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => patchDiffChecker.zipAndConfirmUnpatchableDiffsIfNecessary(
          localArtifactDirectory: any(named: 'localArtifactDirectory'),
          releaseArtifactUrl: Uri.parse(ipaArtifact.url),
          archiveDiffer: archiveDiffer,
          force: false,
        ),
      ).called(1);
      verifyNever(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          channelName: any(named: 'channelName'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      );
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
          appId: any(named: 'appId'),
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
      verify(
        () => codePushClientWrapper.publishPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          channelName: any(named: 'channelName'),
          patchArtifactBundles: any(named: 'patchArtifactBundles'),
        ),
      ).called(1);
      expect(exitCode, ExitCode.success.code);
    });

    test('runs flutter pub get with system flutter after successful build',
        () async {
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      verify(
        () => shorebirdProcess.run(
          'flutter',
          ['--no-version-check', 'pub', 'get', '--offline'],
          runInShell: any(named: 'runInShell'),
          useVendedFlutter: false,
        ),
      ).called(1);
    });

    test('forwards codesign to flutter build', () async {
      when(() => argResults['codesign']).thenReturn(false);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);
      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      verify(
        () => shorebirdProcess.run(
          'flutter',
          any(
            that: containsAllInOrder(
              [
                'build',
                'ipa',
                '--release',
                '--no-codesign',
              ],
            ),
          ),
          runInShell: true,
        ),
      ).called(1);
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
      expect(exitCode, ExitCode.success.code);
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

    test('does not prompt if running on CI', () async {
      when(() => shorebirdEnv.isRunningOnCI).thenReturn(true);
      final tempDir = setUpTempDir();
      setUpTempArtifacts(tempDir);

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(() => logger.confirm(any()));
    });
  });
}

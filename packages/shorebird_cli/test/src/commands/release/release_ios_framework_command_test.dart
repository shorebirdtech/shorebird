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
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../mocks.dart';

void main() {
  group(ReleaseIosFrameworkCommand, () {
    const appId = 'test-app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const flutterVersionAndRevision = '3.10.6 (83305b5088)';
    const versionName = '1.2.3';
    const versionCode = '1';
    const version = '$versionName+$versionCode';
    const appDisplayName = 'Test App';
    const releasePlatform = ReleasePlatform.ios;
    final appMetadata = AppMetadata(
      appId: appId,
      displayName: appDisplayName,
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );
    final release = Release(
      id: 0,
      appId: appId,
      version: version,
      flutterRevision: flutterRevision,
      displayName: '1.2.3+1',
      platformStatuses: {},
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
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
    late Directory projectRoot;
    late Doctor doctor;
    late Platform platform;
    late Auth auth;
    late Progress progress;
    late Logger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterPubGetProcessResult;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdValidator shorebirdValidator;
    late ReleaseIosFrameworkCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    void setUpProjectRoot() {
      File(
        p.join(projectRoot.path, 'pubspec.yaml'),
      ).writeAsStringSync(pubspecYamlContent);
      File(
        p.join(projectRoot.path, 'shorebird.yaml'),
      ).writeAsStringSync('app_id: $appId');
      // Create an xcframework in the release directory to simulate running this
      // command a subsequent time.
      Directory(p.join(projectRoot.path, 'release', 'Flutter.xcframework'))
          .createSync(recursive: true);
      Directory(
        p.join(
          projectRoot.path,
          'build',
          'ios',
          'framework',
          'Release',
          'Flutter.xcframework',
        ),
      ).createSync(recursive: true);
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(ReleasePlatform.ios);
      registerFallbackValue(ReleaseStatus.draft);
      registerFallbackValue(FakeRelease());
      registerFallbackValue(FakeShorebirdProcess());
    });

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      doctor = MockDoctor();
      platform = MockPlatform();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      projectRoot = Directory.systemTemp.createTempSync();
      auth = MockAuth();
      progress = MockProgress();
      logger = MockLogger();
      operatingSystemInterface = MockOperatingSystemInterface();
      flutterBuildProcessResult = MockProcessResult();
      flutterPubGetProcessResult = MockProcessResult();
      flutterValidator = MockShorebirdFlutterValidator();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();

      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
      when(
        () => shorebirdEnv.copyWith(
          flutterRevisionOverride: any(named: 'flutterRevisionOverride'),
        ),
      ).thenAnswer((invocation) {
        when(() => shorebirdEnv.flutterRevision).thenReturn(
          invocation.namedArguments[#flutterRevisionOverride] as String,
        );
        return shorebirdEnv;
      });
      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
      when(() => shorebirdEnv.isRunningOnCI).thenReturn(false);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(
        () => shorebirdFlutter.getVersionAndRevision(),
      ).thenAnswer((_) async => flutterVersionAndRevision);
      when(
        () => shorebirdFlutter.installRevision(
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async => {});
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
      when(() => argResults['release-version']).thenReturn(version);
      when(() => argResults.rest).thenReturn([]);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => doctor.iosCommandValidators).thenReturn([flutterValidator]);
      when(
        () => flutterBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(() => flutterPubGetProcessResult.exitCode)
          .thenReturn(ExitCode.success.code);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => operatingSystemInterface.which('flutter'))
          .thenReturn('/path/to/flutter');
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
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
          supportedOperatingSystems: any(named: 'supportedOperatingSystems'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(ReleaseIosFrameworkCommand.new)
        ..testArgResults = argResults;
    });

    test('supports alpha alias', () {
      expect(command.aliases, contains('ios-framework-alpha'));
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
          validators: any(named: 'validators'),
          supportedOperatingSystems: {Platform.macOS},
        ),
      ).called(1);
    });

    test('exits with explanation if force flag is used', () async {
      when(() => argResults['force']).thenReturn(true);

      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.usage.code)),
      );

      verify(() => logger.err(ReleaseCommand.forceDeprecationErrorMessage))
          .called(1);
      verify(() => logger.info(ReleaseCommand.forceDeprecationExplanation))
          .called(1);
    });

    group('when flutter-version is provided', () {
      const flutterVersion = '3.16.3';
      setUp(() {
        when(() => argResults['flutter-version']).thenReturn(flutterVersion);
      });

      group('when unable to determine flutter revision', () {
        final exception = Exception('oops');
        setUp(() {
          when(
            () => shorebirdFlutter.getRevisionForVersion(any()),
          ).thenThrow(exception);
        });

        test('exits with code 70', () async {
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.software.code));
          verify(
            () => logger.err(
              '''
Unable to determine revision for Flutter version: $flutterVersion.
$exception''',
            ),
          ).called(1);
        });
      });

      group('when flutter version is not supported', () {
        setUp(() {
          when(
            () => shorebirdFlutter.getRevisionForVersion(any()),
          ).thenAnswer((_) async => null);
        });

        test('exits with code 70', () async {
          final exitCode = await runWithOverrides(command.run);
          expect(exitCode, equals(ExitCode.software.code));
          verify(
            () => logger.err(
              any(that: contains('Version $flutterVersion not found.')),
            ),
          ).called(1);
        });
      });

      group('when flutter version is supported', () {
        const revision = '771d07b2cf';
        setUp(() {
          when(
            () => shorebirdFlutter.getRevisionForVersion(any()),
          ).thenAnswer((_) async => revision);
        });

        test('uses specified flutter version build', () async {
          when(
            () => shorebirdProcess.run(
              'flutter',
              any(),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenAnswer((_) async {
            // Ensure we're using the correct flutter version.
            expect(shorebirdEnv.flutterRevision, equals(revision));
            return flutterBuildProcessResult;
          });

          setUpProjectRoot();

          await runWithOverrides(command.run);

          verify(() => shorebirdFlutter.installRevision(revision: revision))
              .called(1);
          verify(
            () => codePushClientWrapper.createRelease(
              appId: appId,
              version: version,
              flutterRevision: revision,
              platform: releasePlatform,
            ),
          ).called(1);
        });

        group('when flutter version install fails', () {
          setUp(() {
            when(
              () => shorebirdFlutter.installRevision(
                revision: any(named: 'revision'),
              ),
            ).thenThrow(Exception('oops'));
          });

          test('exits with code 70', () async {
            setUpProjectRoot();
            final result = await runWithOverrides(command.run);

            expect(result, equals(ExitCode.software.code));
            verify(
              () => shorebirdFlutter.installRevision(revision: revision),
            ).called(1);
          });
        });
      });
    });

    test('exits with code 70 when build fails with non-zero exit code',
        () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oops');

      setUpProjectRoot();
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.software.code));
      verify(
        () => progress.fail(any(that: contains('Failed to build'))),
      ).called(1);
    });

    test('checks that release is not active if release exists', () async {
      when(
        () => codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
      setUpProjectRoot();

      await runWithOverrides(command.run);

      verify(
        () => codePushClientWrapper.ensureReleaseIsNotActive(
          release: release,
          platform: releasePlatform,
        ),
      ).called(1);
    });

    test('aborts when user opts out', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      setUpProjectRoot();

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.success.code);
      verify(() => logger.info('Aborting.')).called(1);
      verifyNever(
        () => codePushClientWrapper.createIosReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          xcarchivePath: any(
            named: 'xcarchivePath',
            that: endsWith('.xcarchive'),
          ),
          runnerPath: any(named: 'runnerPath', that: endsWith('Runner.app')),
          isCodesigned: any(named: 'isCodesigned'),
        ),
      );
    });

    test('does not prompt for confirmation when running on CI', () async {
      when(() => shorebirdEnv.isRunningOnCI).thenReturn(true);
      when(() => argResults['release-version']).thenReturn(version);
      setUpProjectRoot();

      final exitCode = await runWithOverrides(command.run);

      verify(() => logger.success('\n✅ Published Release $version!')).called(1);
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
      setUpProjectRoot();

      final exitCode = await runWithOverrides(command.run);

      verify(() => logger.success('\n✅ Published Release $version!')).called(1);
      verify(
        () => logger.info(
          any(
            that: stringContainsInOrder(
              [
                'Your next step is to add the .xcframework files found in',
                'release',
                'to your iOS app.',
                '''Embed the App.xcframework and ShorebirdFlutter.framework in your Xcode project''',
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
            that: endsWith(
              p.join('release', 'App.xcframework'),
            ),
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

    test('runs flutter pub get with system flutter after successful build',
        () async {
      setUpProjectRoot();

      await runWithOverrides(command.run);

      verify(
        () => shorebirdProcess.run(
          'flutter',
          ['--no-version-check', 'pub', 'get', '--offline'],
          runInShell: any(named: 'runInShell'),
          useVendedFlutter: false,
        ),
      ).called(1);
    });
  });
}

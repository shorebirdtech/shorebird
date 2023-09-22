import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/adb.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/bundletool.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/ios_deploy.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(PreviewCommand, () {
    const appId = 'test-app-id';
    const appDisplayName = 'Test App';
    const releaseVersion = '1.2.3';
    const releaseId = 42;

    late AppMetadata app;
    late ArgResults argResults;
    late ArtifactManager artifactManager;
    late Auth auth;
    late Cache cache;
    late CodePushClientWrapper codePushClientWrapper;
    late Logger logger;
    late Directory previewDirectory;
    late Progress progress;
    late Release release;
    late ReleaseArtifact releaseArtifact;
    late ShorebirdValidator shorebirdValidator;
    late PreviewCommand command;

    R runWithOverrides<R>(R Function() body) {
      return HttpOverrides.runZoned(
        () => runScoped(
          body,
          values: {
            artifactManagerRef.overrideWith(() => artifactManager),
            authRef.overrideWith(() => auth),
            cacheRef.overrideWith(() => cache),
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
            loggerRef.overrideWith(() => logger),
            shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          },
        ),
      );
    }

    setUpAll(() {
      registerFallbackValue(File(''));
      registerFallbackValue(MockHttpClient());
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(StreamController<List<int>>());
      registerFallbackValue(Uri());
    });

    setUp(() {
      app = MockAppMetadata();
      argResults = MockArgResults();
      artifactManager = MockArtifactManager();
      auth = MockAuth();
      cache = MockCache();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockLogger();
      previewDirectory = Directory.systemTemp.createTempSync();
      progress = MockProgress();
      release = MockRelease();
      releaseArtifact = MockReleaseArtifact();
      shorebirdValidator = MockShorebirdValidator();
      command = PreviewCommand()..testArgResults = argResults;

      when(() => argResults['app-id']).thenReturn(appId);
      when(() => argResults['release-version']).thenReturn(releaseVersion);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => cache.getPreviewDirectory(any())).thenReturn(previewDirectory);
      when(
        () => codePushClientWrapper.getApps(),
      ).thenAnswer((_) async => [app]);
      when(
        () => codePushClientWrapper.getReleases(
          appId: any(named: 'appId'),
          sideloadableOnly: any(named: 'sideloadableOnly'),
        ),
      ).thenAnswer((_) async => [release]);
      when(
        () => codePushClientWrapper.getReleaseArtifact(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async => releaseArtifact);
      when(() => app.appId).thenReturn(appId);
      when(() => app.displayName).thenReturn(appDisplayName);
      when(() => release.id).thenReturn(releaseId);
      when(() => release.version).thenReturn(releaseVersion);
      when(() => release.platformStatuses).thenReturn({
        ReleasePlatform.android: ReleaseStatus.active,
        ReleasePlatform.ios: ReleaseStatus.active,
      });
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => progress.fail(any())).thenReturn(null);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
    });

    test('exits when validation fails', () async {
      final exception = ValidationFailedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenThrow(exception);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(exception.exitCode.code)),
      );
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
        ),
      ).called(1);
    });

    test('exits with code 70 when querying for releases fails', () async {
      final exception = Exception('oops');
      when(
        () => codePushClientWrapper.getReleases(
          appId: any(named: 'appId'),
          sideloadableOnly: any(named: 'sideloadableOnly'),
        ),
      ).thenThrow(exception);
      await expectLater(
        () => runWithOverrides(command.run),
        throwsA(exception),
      );
      verify(
        () => codePushClientWrapper.getReleases(
          appId: appId,
          sideloadableOnly: true,
        ),
      ).called(1);
    });

    group('android', () {
      const platform = ReleasePlatform.android;
      const releaseArtifactUrl = 'https://example.com/release.aab';
      const packageName = 'com.example.app';

      late Adb adb;
      late Bundletool bundletool;
      late Process process;

      String aabPath() => p.join(
            previewDirectory.path,
            '${platform.name}_$releaseVersion.aab',
          );

      String apksPath() => p.join(
            previewDirectory.path,
            '${platform.name}_$releaseVersion.apks',
          );

      R runWithOverrides<R>(R Function() body) {
        return HttpOverrides.runZoned(
          () => runScoped(
            body,
            values: {
              adbRef.overrideWith(() => adb),
              artifactManagerRef.overrideWith(() => artifactManager),
              authRef.overrideWith(() => auth),
              bundletoolRef.overrideWith(() => bundletool),
              cacheRef.overrideWith(() => cache),
              codePushClientWrapperRef
                  .overrideWith(() => codePushClientWrapper),
              loggerRef.overrideWith(() => logger),
              shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            },
          ),
        );
      }

      setUp(() {
        adb = MockAdb();
        bundletool = MockBundleTool();
        process = MockProcess();

        when(() => argResults['platform']).thenReturn(platform.name);
        when(
          () => artifactManager.downloadFile(
            any(),
            httpClient: any(named: 'httpClient'),
            outputPath: any(named: 'outputPath'),
          ),
        ).thenAnswer((_) async => '');
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputPath: any(named: 'outputPath'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => bundletool.getPackageName(any()),
        ).thenAnswer((_) async => packageName);
        when(
          () => bundletool.buildApks(
            bundle: any(named: 'bundle'),
            output: any(named: 'output'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => bundletool.installApks(
            apks: any(named: 'apks'),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => adb.startApp(
            package: any(named: 'package'),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => adb.logcat(
            filter: any(named: 'filter'),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenAnswer((_) async => process);
        when(
          () => process.exitCode,
        ).thenAnswer((_) async => ExitCode.success.code);
        when(() => process.stdout).thenAnswer((_) => const Stream.empty());
        when(() => process.stderr).thenAnswer((_) => const Stream.empty());
        when(() => releaseArtifact.url).thenReturn(releaseArtifactUrl);
      });

      test('exits with code 70 when querying for release artifact fails',
          () async {
        final exception = Exception('oops');
        when(
          () => codePushClientWrapper.getReleaseArtifact(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
          ),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(
          () => codePushClientWrapper.getReleaseArtifact(
            appId: appId,
            releaseId: releaseId,
            arch: 'aab',
            platform: platform,
          ),
        ).called(1);
      });

      test('exits with code 70 when downloading release artifact fails',
          () async {
        final exception = Exception('oops');
        when(
          () => artifactManager.downloadFile(
            any(),
            httpClient: any(named: 'httpClient'),
            outputPath: any(named: 'outputPath'),
          ),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => progress.fail('$exception')).called(1);
      });

      test('exits with code 70 when extracting metadata fails', () async {
        final exception = Exception('oops');
        when(() => bundletool.getPackageName(any())).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => bundletool.getPackageName(aabPath())).called(1);
      });

      test('exits with code 70 when building apks fails', () async {
        final exception = Exception('oops');
        when(
          () => bundletool.buildApks(
            bundle: any(named: 'bundle'),
            output: any(named: 'output'),
          ),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(
          () => bundletool.buildApks(bundle: aabPath(), output: apksPath()),
        ).called(1);
      });

      test('exits with code 70 when installing apks fails', () async {
        final exception = Exception('oops');
        when(
          () => bundletool.installApks(apks: any(named: 'apks')),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => bundletool.installApks(apks: apksPath())).called(1);
      });

      test('exits with code 70 when starting app fails', () async {
        final exception = Exception('oops');
        when(() => adb.startApp(package: any(named: 'package')))
            .thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => adb.startApp(package: packageName)).called(1);
      });

      test('exits with non-zero exit code when logcat process fails', () async {
        when(() => process.exitCode).thenAnswer((_) async => 1);
        final result = await runWithOverrides(command.run);
        expect(result, equals(1));
        verify(() => adb.logcat(filter: 'flutter')).called(1);
      });

      test('pipes stdout output to logger', () async {
        final completer = Completer<int>();
        when(() => process.exitCode).thenAnswer((_) => completer.future);
        const output = 'hello world';
        when(
          () => process.stdout,
        ).thenAnswer((_) => Stream.value(utf8.encode(output)));
        final result = runWithOverrides(command.run);
        completer.complete(0);
        await expectLater(await result, equals(ExitCode.success.code));
        verify(() => logger.info(output)).called(1);
      });

      test('pipes stderr output to logger', () async {
        final completer = Completer<int>();
        when(() => process.exitCode).thenAnswer((_) => completer.future);
        const output = 'hello world';
        when(
          () => process.stderr,
        ).thenAnswer((_) => Stream.value(utf8.encode(output)));
        final result = runWithOverrides(command.run);
        completer.complete(0);
        await expectLater(await result, equals(ExitCode.success.code));
        verify(() => logger.err(output)).called(1);
      });

      test('queries for apps when app-id is not specified', () async {
        when(() => argResults['app-id']).thenReturn(null);
        when(
          () => logger.chooseOne<AppMetadata>(
            any(),
            choices: any(named: 'choices'),
            display: any(named: 'display'),
          ),
        ).thenReturn(app);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        final captured = verify(
          () => logger.chooseOne<AppMetadata>(
            any(),
            choices: any(named: 'choices'),
            display: captureAny(named: 'display'),
          ),
        ).captured.single as String Function(AppMetadata);
        expect(captured(app), equals(app.displayName));
        verify(() => codePushClientWrapper.getApps()).called(1);
      });

      test('prompts for platforms when platform is not specified', () async {
        when(() => argResults['platform']).thenReturn(null);
        when(
          () => logger.chooseOne<String>(
            any(),
            choices: any(named: 'choices'),
            display: any(named: 'display'),
          ),
        ).thenReturn(platform.name);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        final platforms = verify(
          () => logger.chooseOne<String>(
            any(),
            choices: captureAny(named: 'choices'),
            display: any(named: 'display'),
          ),
        ).captured.single as List<String>;
        expect(
          platforms,
          equals([
            ReleasePlatform.android.name,
            ReleasePlatform.ios.name,
          ]),
        );
      });

      test('exits early when no apps are found', () async {
        when(() => argResults['app-id']).thenReturn(null);
        when(() => codePushClientWrapper.getApps()).thenAnswer((_) async => []);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verifyNever(
          () => logger.chooseOne<AppMetadata>(
            any(),
            choices: any(named: 'choices'),
            display: captureAny(named: 'display'),
          ),
        );
        verify(() => codePushClientWrapper.getApps()).called(1);
        verify(() => logger.info('No apps found')).called(1);
      });

      test('exits early when no releases are found', () async {
        when(() => argResults['release-version']).thenReturn(null);
        when(
          () => codePushClientWrapper.getReleases(
            appId: any(named: 'appId'),
            sideloadableOnly: any(named: 'sideloadableOnly'),
          ),
        ).thenAnswer((_) async => []);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verifyNever(
          () => logger.chooseOne<AppMetadata>(
            any(),
            choices: any(named: 'choices'),
            display: captureAny(named: 'display'),
          ),
        );
        verify(
          () => codePushClientWrapper.getReleases(
            appId: appId,
            sideloadableOnly: true,
          ),
        ).called(1);
        verify(() => logger.info('No previewable releases found')).called(1);
      });

      test(
          'queries for releases when '
          'release-version is not specified', () async {
        when(() => argResults['release-version']).thenReturn(null);
        when(
          () => logger.chooseOne<Release>(
            any(),
            choices: any(named: 'choices'),
            display: any(named: 'display'),
          ),
        ).thenReturn(release);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        final captured = verify(
          () => logger.chooseOne<Release>(
            any(),
            choices: any(named: 'choices'),
            display: captureAny(named: 'display'),
          ),
        ).captured.single as String Function(Release);
        expect(captured(release), equals(releaseVersion));
        verify(
          () => codePushClientWrapper.getReleases(
            appId: appId,
            sideloadableOnly: true,
          ),
        ).called(1);
      });

      test('forwards deviceId to adb and bundletool', () async {
        const deviceId = '1234';
        when(() => argResults['device-id']).thenReturn(deviceId);
        await runWithOverrides(command.run);

        verify(
          () => bundletool.installApks(
            apks: any(named: 'apks'),
            deviceId: deviceId,
          ),
        ).called(1);
        verify(
          () => adb.startApp(
            package: any(named: 'package'),
            deviceId: deviceId,
          ),
        ).called(1);
        verify(
          () => adb.logcat(filter: any(named: 'filter'), deviceId: deviceId),
        ).called(1);
      });
    });

    group('ios', () {
      const releaseArtifactUrl = 'https://example.com/runner.app';
      const platform = ReleasePlatform.ios;
      late IOSDeploy iosDeploy;

      String runnerPath() => p.join(
            previewDirectory.path,
            '${platform.name}_$releaseVersion.app',
          );

      R runWithOverrides<R>(R Function() body) {
        return HttpOverrides.runZoned(
          () => runScoped(
            body,
            values: {
              adbRef.overrideWith(() => adb),
              artifactManagerRef.overrideWith(() => artifactManager),
              authRef.overrideWith(() => auth),
              bundletoolRef.overrideWith(() => bundletool),
              cacheRef.overrideWith(() => cache),
              codePushClientWrapperRef
                  .overrideWith(() => codePushClientWrapper),
              iosDeployRef.overrideWith(() => iosDeploy),
              loggerRef.overrideWith(() => logger),
              shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            },
          ),
        );
      }

      setUp(() {
        iosDeploy = MockIOSDeploy();
        when(() => argResults['platform']).thenReturn(platform.name);
        when(
          () => artifactManager.downloadFile(
            any(),
            httpClient: any(named: 'httpClient'),
          ),
        ).thenAnswer((_) async => '');
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputPath: any(named: 'outputPath'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => iosDeploy.installAndLaunchApp(
            bundlePath: any(named: 'bundlePath'),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenAnswer((_) async => ExitCode.success.code);
        when(() => releaseArtifact.url).thenReturn(releaseArtifactUrl);
      });

      test('exits with code 70 when querying for release artifact fails',
          () async {
        final exception = Exception('oops');
        when(
          () => codePushClientWrapper.getReleaseArtifact(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            arch: any(named: 'arch'),
            platform: any(named: 'platform'),
          ),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(
          () => codePushClientWrapper.getReleaseArtifact(
            appId: appId,
            releaseId: releaseId,
            arch: 'runner',
            platform: platform,
          ),
        ).called(1);
      });

      test('exits with code 70 when downloading release artifact fails',
          () async {
        final exception = Exception('oops');
        when(
          () => artifactManager.downloadFile(
            any(),
            httpClient: any(named: 'httpClient'),
          ),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => progress.fail('$exception')).called(1);
      });

      test(
          'exits with code 70 when extracting '
          'release artifact fails', () async {
        final exception = Exception('oops');
        when(
          () => artifactManager.extractZip(
            zipFile: any(named: 'zipFile'),
            outputPath: any(named: 'outputPath'),
          ),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => progress.fail('$exception')).called(1);
      });

      test('exits with code 70 when install/launch throws', () async {
        final exception = Exception('oops');
        when(
          () => iosDeploy.installAndLaunchApp(
            bundlePath: any(named: 'bundlePath'),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(
          () => iosDeploy.installAndLaunchApp(bundlePath: runnerPath()),
        ).called(1);
      });

      test('exits with code 0 when install/launch succeeds', () async {
        when(
          () => iosDeploy.installAndLaunchApp(
            bundlePath: any(named: 'bundlePath'),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenAnswer((_) async => ExitCode.success.code);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => iosDeploy.installAndLaunchApp(bundlePath: runnerPath()),
        ).called(1);
      });
    });
  });
}

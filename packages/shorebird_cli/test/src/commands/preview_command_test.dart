import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/adb.dart';
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

class _MockAdb extends Mock implements Adb {}

class _MockAppMetadata extends Mock implements AppMetadata {}

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockBundletool extends Mock implements Bundletool {}

class _MockCache extends Mock implements Cache {}

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockHttpClient extends Mock implements HttpClient {}

class _MockHttpClientRequest extends Mock implements HttpClientRequest {}

class _MockHttpClientResponse extends Mock implements HttpClientResponse {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockProcess extends Mock implements Process {}

class _MockRelease extends Mock implements Release {}

class _MockReleaseArtifact extends Mock implements ReleaseArtifact {}

class _MockIOSDeploy extends Mock implements IOSDeploy {}

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

void main() {
  group(PreviewCommand, () {
    const appId = 'test-app-id';
    const appDisplayName = 'Test App';
    const releaseVersion = '1.2.3';
    const releaseId = 42;

    late AppMetadata app;
    late ArgResults argResults;
    late Auth auth;
    late Cache cache;
    late CodePushClientWrapper codePushClientWrapper;
    late HttpClient httpClient;
    late HttpClientRequest httpClientRequest;
    late HttpClientResponse httpClientResponse;
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
            authRef.overrideWith(() => auth),
            cacheRef.overrideWith(() => cache),
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
            loggerRef.overrideWith(() => logger),
            shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          },
        ),
        createHttpClient: (_) => httpClient,
      );
    }

    setUpAll(() {
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(StreamController<List<int>>());
      registerFallbackValue(Uri());
    });

    setUp(() {
      app = _MockAppMetadata();
      argResults = _MockArgResults();
      auth = _MockAuth();
      cache = _MockCache();
      codePushClientWrapper = _MockCodePushClientWrapper();
      httpClient = _MockHttpClient();
      httpClientRequest = _MockHttpClientRequest();
      httpClientResponse = _MockHttpClientResponse();
      logger = _MockLogger();
      previewDirectory = Directory.systemTemp.createTempSync();
      progress = _MockProgress();
      release = _MockRelease();
      releaseArtifact = _MockReleaseArtifact();
      shorebirdValidator = _MockShorebirdValidator();
      command = PreviewCommand()..testArgResults = argResults;

      when(() => argResults['app-id']).thenReturn(appId);
      when(() => argResults['release-version']).thenReturn(releaseVersion);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => cache.getPreviewDirectory(any())).thenReturn(previewDirectory);
      when(
        () => codePushClientWrapper.getApps(),
      ).thenAnswer((_) async => [app]);
      when(
        () => codePushClientWrapper.getReleases(appId: appId),
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
        () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
      ).thenThrow(exception);
      await expectLater(
        () => runWithOverrides(command.run),
        throwsA(exception),
      );
      verify(
        () => codePushClientWrapper.getReleases(appId: appId),
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
              authRef.overrideWith(() => auth),
              bundletoolRef.overrideWith(() => bundletool),
              cacheRef.overrideWith(() => cache),
              codePushClientWrapperRef
                  .overrideWith(() => codePushClientWrapper),
              loggerRef.overrideWith(() => logger),
              shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            },
          ),
          createHttpClient: (_) => httpClient,
        );
      }

      setUp(() {
        adb = _MockAdb();
        bundletool = _MockBundletool();
        process = _MockProcess();

        when(() => argResults['platform']).thenReturn(platform.name);
        when(
          () => httpClient.getUrl(any()),
        ).thenAnswer((_) async => httpClientRequest);
        when(
          () => httpClientRequest.close(),
        ).thenAnswer((_) async => httpClientResponse);
        when(() => httpClientResponse.statusCode).thenReturn(HttpStatus.ok);
        when(() => httpClientResponse.pipe(any())).thenAnswer((_) async {});
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
          () => bundletool.installApks(apks: any(named: 'apks')),
        ).thenAnswer((_) async {});
        when(() => adb.startApp(any())).thenAnswer((_) async {});
        when(
          () => adb.logcat(filter: any(named: 'filter')),
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
        when(() => httpClient.getUrl(any())).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => httpClient.getUrl(Uri.parse(releaseArtifactUrl)))
            .called(1);
      });

      test(
          'exits with code 70 when downloading release artifact '
          'returns non-200 response', () async {
        when(
          () => httpClientResponse.statusCode,
        ).thenReturn(HttpStatus.badRequest);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => httpClientRequest.close()).called(1);
        verify(() => httpClientResponse.statusCode).called(1);
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
        when(() => adb.startApp(any())).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => adb.startApp(packageName)).called(1);
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
          () => codePushClientWrapper.getReleases(appId: any(named: 'appId')),
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
        verify(() => codePushClientWrapper.getReleases(appId: appId)).called(1);
        verify(() => logger.info('No releases found')).called(1);
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
        verify(() => codePushClientWrapper.getReleases(appId: appId)).called(1);
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
          createHttpClient: (_) => httpClient,
        );
      }

      setUp(() {
        iosDeploy = _MockIOSDeploy();
        when(() => argResults['platform']).thenReturn(platform.name);
        when(
          () => httpClient.getUrl(any()),
        ).thenAnswer((_) async => httpClientRequest);
        when(
          () => httpClientRequest.close(),
        ).thenAnswer((_) async => httpClientResponse);
        when(() => httpClientResponse.statusCode).thenReturn(HttpStatus.ok);
        when(() => httpClientResponse.pipe(any()))
            .thenAnswer((invocation) async {
          (invocation.positionalArguments.single as IOSink)
              .add(ZipEncoder().encode(Archive())!);
          // Wait 1 tick for the content to be written.
          await Future<void>.delayed(Duration.zero);
        });
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
        when(() => httpClient.getUrl(any())).thenThrow(exception);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(
          () => httpClient.getUrl(Uri.parse(releaseArtifactUrl)),
        ).called(1);
      });

      test(
          'exits with code 70 when downloading release artifact '
          'returns non-200 response', () async {
        when(
          () => httpClientResponse.statusCode,
        ).thenReturn(HttpStatus.badRequest);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => httpClientRequest.close()).called(1);
        verify(() => httpClientResponse.statusCode).called(1);
      });

      test(
          'exits with code 70 when extracting '
          'release artifact fails', () async {
        when(
          () => httpClientResponse.pipe(any()),
        ).thenThrow(Exception());
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
        verify(() => httpClientRequest.close()).called(1);
        verify(() => httpClientResponse.statusCode).called(1);
        verify(() => httpClientResponse.pipe(any())).called(1);
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

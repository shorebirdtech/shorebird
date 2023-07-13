import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:shorebird_cli/src/logger.dart';
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

void main() {
  group(PreviewCommand, () {
    const appId = 'test-app-id';
    const appDisplayName = 'Test App';
    const platform = 'android';
    const releaseVersion = '1.2.3';
    const releaseId = 42;
    const releaseArtifactUrl = 'https://example.com/release.aab';
    const packageName = 'com.example.app';

    late Adb adb;
    late AppMetadata app;
    late ArgResults argResults;
    late Auth auth;
    late Bundletool bundletool;
    late Cache cache;
    late CodePushClientWrapper codePushClientWrapper;
    late HttpClient httpClient;
    late HttpClientRequest httpClientRequest;
    late HttpClientResponse httpClientResponse;
    late Logger logger;
    late Directory previewDirectory;
    late Process process;
    late Progress progress;
    late Release release;
    late ReleaseArtifact releaseArtifact;
    late PreviewCommand command;

    R runWithOverrides<R>(R Function() body) {
      return HttpOverrides.runZoned(
        () => runScoped(
          body,
          values: {
            adbRef.overrideWith(() => adb),
            authRef.overrideWith(() => auth),
            bundletoolRef.overrideWith(() => bundletool),
            cacheRef.overrideWith(() => cache),
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
            loggerRef.overrideWith(() => logger),
          },
        ),
        createHttpClient: (_) => httpClient,
      );
    }

    String aabPath() => p.join(
          previewDirectory.path,
          '${platform}_$releaseVersion.aab',
        );

    String apksPath() => p.join(
          previewDirectory.path,
          '${platform}_$releaseVersion.apks',
        );

    setUpAll(() {
      registerFallbackValue(Uri());
      registerFallbackValue(StreamController<List<int>>());
    });

    setUp(() {
      adb = _MockAdb();
      app = _MockAppMetadata();
      argResults = _MockArgResults();
      auth = _MockAuth();
      bundletool = _MockBundletool();
      cache = _MockCache();
      codePushClientWrapper = _MockCodePushClientWrapper();
      httpClient = _MockHttpClient();
      httpClientRequest = _MockHttpClientRequest();
      httpClientResponse = _MockHttpClientResponse();
      logger = _MockLogger();
      previewDirectory = Directory.systemTemp.createTempSync();
      process = _MockProcess();
      progress = _MockProgress();
      release = _MockRelease();
      releaseArtifact = _MockReleaseArtifact();
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
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
      when(
        () => codePushClientWrapper.getReleaseArtifact(
          releaseId: any(named: 'releaseId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async => releaseArtifact);
      when(() => app.appId).thenReturn(appId);
      when(() => app.displayName).thenReturn(appDisplayName);
      when(() => release.id).thenReturn(releaseId);
      when(() => release.version).thenReturn(releaseVersion);
      when(() => releaseArtifact.url).thenReturn(releaseArtifactUrl);
      when(() => logger.progress(any())).thenReturn(progress);
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
    });

    test('returns no user error when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      final result = await runWithOverrides(command.run);
      expect(result, ExitCode.noUser.code);
    });

    test('exits with code 70 when querying for release fails', () async {
      final exception = Exception('oops');
      when(
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenThrow(exception);
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.software.code));
      verify(
        () => codePushClientWrapper.getRelease(
          appId: appId,
          releaseVersion: releaseVersion,
        ),
      ).called(1);
    });

    test('exits with code 70 when querying for release artifact fails',
        () async {
      final exception = Exception('oops');
      when(
        () => codePushClientWrapper.getReleaseArtifact(
          releaseId: any(named: 'releaseId'),
          arch: any(named: 'arch'),
          platform: any(named: 'platform'),
        ),
      ).thenThrow(exception);
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.software.code));
      verify(
        () => codePushClientWrapper.getReleaseArtifact(
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
      verify(() => httpClient.getUrl(Uri.parse(releaseArtifactUrl))).called(1);
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
}

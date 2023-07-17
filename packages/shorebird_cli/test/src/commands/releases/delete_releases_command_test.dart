import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/releases/releases.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

void main() {
  group(DeleteReleasesCommand, () {
    const appId = 'test-app-id';
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const releaseId = 3;
    const versionNumber = '1.0.0';

    const pubspecYamlContent = '''
name: example
version: 1.0.1
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  assets:
    - shorebird.yaml''';

    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late Logger logger;
    late CodePushClient codePushClient;
    late Progress progress;
    late DeleteReleasesCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          loggerRef.overrideWith(() => logger)
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
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      logger = _MockLogger();
      codePushClient = _MockCodePushClient();
      progress = _MockProgress();

      when(() => argResults['version']).thenReturn(versionNumber);

      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);

      when(() => codePushClient.getReleases(appId: any(named: 'appId')))
          .thenAnswer(
        (_) async => [
          const Release(
            id: 1,
            appId: appId,
            version: '0.1.0',
            flutterRevision: flutterRevision,
            displayName: null,
          ),
          const Release(
            id: 2,
            appId: appId,
            version: '0.1.1',
            flutterRevision: flutterRevision,
            displayName: null,
          ),
          const Release(
            id: releaseId,
            appId: appId,
            version: versionNumber,
            flutterRevision: flutterRevision,
            displayName: null,
          ),
        ],
      );

      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);

      command = runWithOverrides(
        () => DeleteReleasesCommand(
          buildCodePushClient: ({
            required http.Client httpClient,
            Uri? hostedUri,
          }) {
            return codePushClient;
          },
        ),
      )..testArgResults = argResults;
    });

    test('returns correct description', () {
      expect(
        command.description,
        'Delete the specified release version.',
      );
    });

    test('returns no user error when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);

      final result = await runWithOverrides(command.run);

      expect(result, ExitCode.noUser.code);
    });

    test('returns config exit code if shorebird.yaml is not present', () async {
      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.config.code);
    });

    test('prompts for version when not provided', () async {
      when(() => argResults['version']).thenReturn(null);
      when(() => logger.prompt(any())).thenReturn(versionNumber);

      final tempDir = setUpTempDir();
      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      verify(
        () => logger.prompt(
          any(that: contains('Which version would you like to delete?')),
        ),
      ).called(1);
    });

    test('does not prompt for version if user provides it with a flag',
        () async {
      final tempDir = setUpTempDir();
      await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      verifyNever(() => logger.prompt(any()));
    });

    test('returns software exit code if get releases request fails', () async {
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenThrow(Exception('oops'));

      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.software.code);
    });

    test('aborts when user does not confirm', () async {
      when(() => logger.confirm(any())).thenReturn(false);

      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
      verifyNever(
        () => codePushClient.deleteRelease(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      );
      verify(() => logger.info('Aborted.')).called(1);
    });

    test('returns software error when release is not found', () async {
      when(() => argResults['version']).thenReturn('asdf');

      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.software.code);
      verify(() => logger.err('No release found for version "asdf"')).called(1);
      verifyNever(
        () => codePushClient.deleteRelease(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      );
    });

    test('returns software error when delete release fails', () async {
      when(
        () => codePushClient.deleteRelease(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      ).thenThrow(Exception('oops'));

      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.software.code);
      verify(() => progress.fail(any(that: contains('oops')))).called(1);
      verify(
        () => codePushClient.deleteRelease(appId: appId, releaseId: releaseId),
      ).called(1);
    });

    test('returns success when release is deleted', () async {
      when(
        () => codePushClient.deleteRelease(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      ).thenAnswer((_) async {});

      final tempDir = setUpTempDir();
      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
      verify(
        () => codePushClient.deleteRelease(appId: appId, releaseId: releaseId),
      ).called(1);
      verify(
        () => progress.complete('Deleted release $versionNumber.'),
      ).called(1);
    });

    test('uses correct app_id when flavor is specified', () async {
      const flavor = 'development';
      when(() => argResults['flavor']).thenReturn(flavor);
      final tempDir = setUpTempDir();
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('''
app_id: productionAppId
flavors:
  $flavor: $appId''');
      when(
        () => codePushClient.deleteRelease(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      ).thenAnswer((_) async {});

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
      verify(() => codePushClient.getReleases(appId: appId)).called(1);
      verify(
        () => codePushClient.deleteRelease(appId: appId, releaseId: releaseId),
      ).called(1);
      verify(
        () => progress.complete('Deleted release $versionNumber.'),
      ).called(1);
    });
  });
}

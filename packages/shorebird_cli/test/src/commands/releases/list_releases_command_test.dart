import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockLogger extends Mock implements Logger {}

void main() {
  group(ListReleasesCommand, () {
    const appId = 'test-app-id';
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';

    late ArgResults argResults;
    late Auth auth;
    late http.Client httpClient;
    late CodePushClient codePushClient;
    late Logger logger;
    late ListReleasesCommand command;

    const pubspecYamlContent = '''
name: example
version: 1.0.1
environment:
  sdk: ">=2.19.0 <3.0.0"
  
flutter:
  assets:
    - shorebird.yaml''';

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
      auth = _MockAuth();
      codePushClient = _MockCodePushClient();
      httpClient = _MockHttpClient();
      logger = _MockLogger();

      when(() => auth.client).thenReturn(httpClient);
      when(() => auth.isAuthenticated).thenReturn(true);

      command = runWithOverrides(
        () => ListReleasesCommand(
          buildCodePushClient: ({required httpClient, hostedUri}) {
            return codePushClient;
          },
        ),
      )..testArgResults = argResults;
    });

    test('description is correct', () {
      expect(command.description, equals('List all releases for this app.'));
    });

    test('returns ExitCode.noUser when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      expect(await runWithOverrides(command.run), ExitCode.noUser.code);
    });

    test('returns ExitCode.config when shorebird is not initialized', () async {
      final exitCode = await runWithOverrides(command.run);

      verify(
        () => logger.err(
          any(
            that: stringContainsInOrder([
              'Shorebird is not initialized. Did you run',
              'shorebird init',
            ]),
          ),
        ),
      ).called(1);
      expect(exitCode, ExitCode.config.code);
    });

    test('returns ExitCode.software when unable to get releases', () async {
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenThrow(Exception());
      final tempDir = setUpTempDir();

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.software.code);
    });

    test('returns ExitCode.success when releases is empty', () async {
      when(() => codePushClient.getReleases(appId: appId))
          .thenAnswer((_) async => []);
      final tempDir = setUpTempDir();

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
      verify(() => logger.info('(empty)')).called(1);
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
      when(() => codePushClient.getReleases(appId: appId)).thenAnswer(
        (_) async => [
          const Release(
            id: 1,
            appId: appId,
            version: '1.0.0',
            flutterRevision: flutterRevision,
            displayName: 'v1.0.0 (dev)',
            platformStatuses: {ReleasePlatform.ios: ReleaseStatus.draft},
          ),
        ],
      );

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
      verify(
        () => logger.info('''
┌─────────┬──────────────┐
│ Version │ Name         │
├─────────┼──────────────┤
│ 1.0.0   │ v1.0.0 (dev) │
└─────────┴──────────────┘'''),
      ).called(1);
    });

    test('returns ExitCode.success and prints releases when releases exist',
        () async {
      final tempDir = setUpTempDir();

      when(() => codePushClient.getReleases(appId: appId)).thenAnswer(
        (_) async => [
          const Release(
            id: 1,
            appId: appId,
            version: '1.0.1',
            flutterRevision: flutterRevision,
            displayName: 'First',
            platformStatuses: {ReleasePlatform.ios: ReleaseStatus.active},
          ),
          const Release(
            id: 1,
            appId: appId,
            version: '1.0.2',
            flutterRevision: flutterRevision,
            displayName: null,
            platformStatuses: {ReleasePlatform.ios: ReleaseStatus.draft},
          ),
        ],
      );

      final exitCode = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );

      expect(exitCode, ExitCode.success.code);
      verify(
        () => logger.info('''
┌─────────┬───────┐
│ Version │ Name  │
├─────────┼───────┤
│ 1.0.1   │ First │
├─────────┼───────┤
│ 1.0.2   │ --    │
└─────────┴───────┘'''),
      ).called(1);
    });
  });
}

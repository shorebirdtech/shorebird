import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockLogger extends Mock implements Logger {}

void main() {
  group('list', () {
    late http.Client httpClient;
    late Auth auth;
    late CodePushClient codePushClient;
    late Logger logger;

    late ListAppsCommand command;

    setUp(() {
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      codePushClient = _MockCodePushClient();
      logger = _MockLogger();
      command = ListAppsCommand(
        auth: auth,
        buildCodePushClient: ({
          required http.Client httpClient,
          Uri? hostedUri,
        }) {
          return codePushClient;
        },
        logger: logger,
      );

      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
    });

    test('description is correct', () {
      expect(command.description, equals('List all apps using Shorebird.'));
    });

    test('returns ExitCode.noUser when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      expect(await command.run(), ExitCode.noUser.code);
    });

    test('returns ExitCode.software when unable to get apps', () async {
      when(() => codePushClient.getApps()).thenThrow(Exception());
      expect(await command.run(), ExitCode.software.code);
    });

    test('returns ExitCode.success when apps are empty', () async {
      when(() => codePushClient.getApps()).thenAnswer((_) async => []);
      expect(await command.run(), ExitCode.success.code);
      verify(() => logger.info('(empty)')).called(1);
    });

    test('returns ExitCode.success when apps are not empty', () async {
      final apps = [
        const AppMetadata(
          appId: '30370f27-dbf1-4673-8b20-fb096e38dffa',
          displayName: 'Shorebird Counter',
          latestReleaseVersion: '1.0.0',
          latestPatchNumber: 1,
        ),
        const AppMetadata(
          appId: '05b45471-a5f3-48cd-b26a-da29d95914a7',
          displayName: 'Shorebird Clock',
        ),
      ];
      when(() => codePushClient.getApps()).thenAnswer((_) async => apps);
      expect(await command.run(), ExitCode.success.code);
      verify(
        () => logger.info(
          '''
┌───────────────────┬──────────────────────────────────────┬─────────┬───────┐
│ Name              │ ID                                   │ Release │ Patch │
├───────────────────┼──────────────────────────────────────┼─────────┼───────┤
│ Shorebird Clock   │ 05b45471-a5f3-48cd-b26a-da29d95914a7 │ --      │ --    │
├───────────────────┼──────────────────────────────────────┼─────────┼───────┤
│ Shorebird Counter │ 30370f27-dbf1-4673-8b20-fb096e38dffa │ 1.0.0   │ 1     │
└───────────────────┴──────────────────────────────────────┴─────────┴───────┘''',
        ),
      ).called(1);
    });

    test('sort apps by display name', () async {
      final unsortedApps = [
        const AppMetadata(
          appId: 'e0e32628-65b8-4df8-90e5-992de49d2d6d',
          displayName: '2',
        ),
        const AppMetadata(
          appId: '28843985-afde-451c-814f-21dbd6824d61',
          displayName: '3',
        ),
        const AppMetadata(
          appId: 'a13c951f-8360-4a8e-a78c-c0f5ee4e88fb',
          displayName: '1',
        ),
      ];
      when(() => codePushClient.getApps())
          .thenAnswer((_) async => unsortedApps);

      expect(await command.run(), ExitCode.success.code);
      verify(
        () => logger.info(
          '''
┌──────┬──────────────────────────────────────┬─────────┬───────┐
│ Name │ ID                                   │ Release │ Patch │
├──────┼──────────────────────────────────────┼─────────┼───────┤
│ 1    │ a13c951f-8360-4a8e-a78c-c0f5ee4e88fb │ --      │ --    │
├──────┼──────────────────────────────────────┼─────────┼───────┤
│ 2    │ e0e32628-65b8-4df8-90e5-992de49d2d6d │ --      │ --    │
├──────┼──────────────────────────────────────┼─────────┼───────┤
│ 3    │ 28843985-afde-451c-814f-21dbd6824d61 │ --      │ --    │
└──────┴──────────────────────────────────────┴─────────┴───────┘''',
        ),
      ).called(1);
    });
  });
}

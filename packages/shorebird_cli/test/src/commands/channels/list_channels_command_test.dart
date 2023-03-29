import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/session.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockLogger extends Mock implements Logger {}

void main() {
  group('list', () {
    const session = Session(apiKey: 'test-api-key');
    const appId = 'test-app-id';

    late ArgResults argResults;
    late Auth auth;
    late CodePushClient codePushClient;
    late Logger logger;
    late ListChannelsCommand command;

    setUp(() {
      argResults = _MockArgResults();
      auth = _MockAuth();
      codePushClient = _MockCodePushClient();
      logger = _MockLogger();
      command = ListChannelsCommand(
        auth: auth,
        buildCodePushClient: ({required String apiKey, Uri? hostedUri}) {
          return codePushClient;
        },
        logger: logger,
      )..testArgResults = argResults;

      when(() => argResults['app-id']).thenReturn(appId);
      when(() => auth.currentSession).thenReturn(session);
    });

    test('description is correct', () {
      expect(
        command.description,
        equals('List all channels for a Shorebird app.'),
      );
    });

    test('returns ExitCode.noUser when not logged in', () async {
      when(() => auth.currentSession).thenReturn(null);
      expect(await command.run(), ExitCode.noUser.code);
    });

    test('returns ExitCode.usage when app id is missing.', () async {
      when(() => argResults['app-id']).thenReturn(null);
      expect(await command.run(), ExitCode.usage.code);
    });

    test('returns ExitCode.software when unable to get channels', () async {
      when(
        () => codePushClient.getChannels(appId: any(named: 'appId')),
      ).thenThrow(Exception());
      expect(await command.run(), ExitCode.software.code);
    });

    test('returns ExitCode.success when channels are empty', () async {
      when(
        () => codePushClient.getChannels(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      expect(await command.run(), ExitCode.success.code);
      verify(() => logger.info('(empty)')).called(1);
    });

    test('returns ExitCode.success when channels are not empty', () async {
      final channels = [
        const Channel(id: 0, appId: appId, name: 'stable'),
        const Channel(id: 1, appId: appId, name: 'development'),
      ];
      when(
        () => codePushClient.getChannels(appId: any(named: 'appId')),
      ).thenAnswer((_) async => channels);
      expect(await command.run(), ExitCode.success.code);
      verify(
        () => logger.info(
          '''
📱 App ID: ${lightCyan.wrap(appId)}
📺 Channels''',
        ),
      ).called(1);
      verify(
        () => logger.info(
          '''
┌─────────────┐
│ Name        │
├─────────────┤
│ stable      │
├─────────────┤
│ development │
└─────────────┘''',
        ),
      ).called(1);
    });
  });
}

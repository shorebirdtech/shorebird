import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockLogger extends Mock implements Logger {}

void main() {
  group('collborators list', () {
    const appId = 'test-app-id';

    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late CodePushClient codePushClient;
    late Logger logger;
    late ListCollaboratorsCommand command;

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      codePushClient = _MockCodePushClient();
      logger = _MockLogger();
      command = ListCollaboratorsCommand(
        auth: auth,
        buildCodePushClient: ({
          required http.Client httpClient,
          Uri? hostedUri,
        }) {
          return codePushClient;
        },
        logger: logger,
      )..testArgResults = argResults;

      when(() => argResults['app-id']).thenReturn(appId);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
    });

    test('description is correct', () {
      expect(
        command.description,
        equals('List all collaborators for a Shorebird app.'),
      );
    });

    test('alias is correct', () {
      expect(command.aliases, equals(['ls']));
    });

    test('returns ExitCode.noUser when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      expect(await command.run(), ExitCode.noUser.code);
    });

    test('returns ExitCode.usage when app id is missing.', () async {
      when(() => argResults['app-id']).thenReturn(null);
      expect(await command.run(), ExitCode.usage.code);
    });

    test('returns ExitCode.software when unable to get collaborators',
        () async {
      when(
        () => codePushClient.getCollaborators(appId: any(named: 'appId')),
      ).thenThrow(Exception());
      expect(await command.run(), ExitCode.software.code);
    });

    test('returns ExitCode.success when collaborators are empty', () async {
      when(
        () => codePushClient.getCollaborators(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      expect(await command.run(), ExitCode.success.code);
      verify(() => logger.info('(empty)')).called(1);
    });

    test('returns ExitCode.success when collaborators are not empty', () async {
      final collaborators = [
        const Collaborator(userId: 0, email: 'jane.doe@shorebird.dev'),
        const Collaborator(userId: 1, email: 'john.doe@shorebird.dev'),
      ];
      when(
        () => codePushClient.getCollaborators(appId: any(named: 'appId')),
      ).thenAnswer((_) async => collaborators);
      expect(await command.run(), ExitCode.success.code);
      verify(
        () => logger.info(
          '''
📱 App ID: ${lightCyan.wrap(appId)}
🤝 Collaborators''',
        ),
      ).called(1);
      verify(
        () => logger.info(
          '''
┌────────────────────────┐
│ Email                  │
├────────────────────────┤
│ jane.doe@shorebird.dev │
├────────────────────────┤
│ john.doe@shorebird.dev │
└────────────────────────┘''',
        ),
      ).called(1);
    });
  });
}

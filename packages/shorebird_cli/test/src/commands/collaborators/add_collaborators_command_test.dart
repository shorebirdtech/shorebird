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

class _MockProgress extends Mock implements Progress {}

void main() {
  group('create', () {
    const appId = 'test-app-id';
    const email = 'jane.doe@shorebird.dev';

    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late CodePushClient codePushClient;
    late Logger logger;
    late Progress progress;
    late AddCollaboratorsCommand command;

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      codePushClient = _MockCodePushClient();
      logger = _MockLogger();
      progress = _MockProgress();
      command = AddCollaboratorsCommand(
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
      when(() => argResults['email']).thenReturn(email);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);
    });

    test('name is correct', () {
      expect(command.name, equals('add'));
    });

    test('description is correct', () {
      expect(
        command.description,
        equals('Add a new collaborator to a Shorebird app.'),
      );
    });

    test('returns ExitCode.noUser when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      expect(await command.run(), ExitCode.noUser.code);
    });

    test('returns ExitCode.usage when app id is missing.', () async {
      when(() => argResults['app-id']).thenReturn(null);
      expect(await command.run(), ExitCode.usage.code);
    });

    test('returns ExitCode.success when user aborts', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      expect(await command.run(), ExitCode.success.code);
      verify(() => logger.info('Aborted.')).called(1);
      verifyNever(
        () => codePushClient.createCollaborator(
          appId: any(named: 'appId'),
          email: any(named: 'email'),
        ),
      );
    });

    test(
        'returns ExitCode.software '
        'when adding a collaborator fails', () async {
      const error = 'oops something went wrong';
      when(
        () => codePushClient.createCollaborator(
          appId: any(named: 'appId'),
          email: any(named: 'email'),
        ),
      ).thenThrow(error);
      expect(await command.run(), ExitCode.software.code);
      verify(() => logger.err(error)).called(1);
    });

    test('prompts for email when not provided', () async {
      when(() => argResults['email']).thenReturn(null);
      when(() => logger.prompt(any())).thenReturn(email);
      when(
        () => codePushClient.createCollaborator(
          appId: any(named: 'appId'),
          email: any(named: 'email'),
        ),
      ).thenAnswer((_) async {});
      expect(await command.run(), ExitCode.success.code);
      verify(
        () => logger.prompt(
          '''${lightGreen.wrap('?')} What is the email of the collaborator you would like to add?''',
        ),
      ).called(1);
      verify(
        () => codePushClient.createCollaborator(appId: appId, email: email),
      ).called(1);
    });

    test('returns ExitCode.success on success', () async {
      when(
        () => codePushClient.createCollaborator(
          appId: any(named: 'appId'),
          email: any(named: 'email'),
        ),
      ).thenAnswer((_) async {});
      expect(await command.run(), ExitCode.success.code);
      verify(() => logger.success('\n✅ New Collaborator Added!')).called(1);
    });
  });
}

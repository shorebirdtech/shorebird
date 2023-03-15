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
  group('delete', () {
    const apiKey = 'test-api-key';
    const appId = 'example';
    const session = Session(apiKey: apiKey);

    late ArgResults argResults;
    late Auth auth;
    late Logger logger;
    late CodePushClient codePushClient;
    late DeleteAppCommand command;

    setUp(() {
      argResults = _MockArgResults();
      auth = _MockAuth();
      logger = _MockLogger();
      codePushClient = _MockCodePushClient();
      command = DeleteAppCommand(
        auth: auth,
        buildCodePushClient: ({required String apiKey}) => codePushClient,
        logger: logger,
      )..testArgResults = argResults;

      when(() => auth.currentSession).thenReturn(session);
    });

    test('returns correct description', () {
      expect(
        command.description,
        equals('Delete an existing app on Shorebird.'),
      );
    });

    test('returns no user error when not logged in', () async {
      when(() => auth.currentSession).thenReturn(null);
      final result = await command.run();
      expect(result, ExitCode.noUser.code);
    });

    test('prompts for app-id when not provided', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      when(() => logger.prompt(any())).thenReturn(appId);
      await command.run();
      verify(() => logger.prompt(any())).called(1);
    });

    test('uses provided app-id when provided', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      when(() => argResults['app-id']).thenReturn(appId);
      await command.run();
      verifyNever(() => logger.prompt(any()));
    });

    test('aborts when user does not confirm', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      when(() => argResults['app-id']).thenReturn(appId);
      final result = await command.run();
      expect(result, ExitCode.success.code);
      verifyNever(() => codePushClient.deleteApp(appId: appId));
      verify(() => logger.info('Aborted.')).called(1);
    });

    test('returns success when app is deleted', () async {
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => argResults['app-id']).thenReturn(appId);
      when(
        () => codePushClient.deleteApp(appId: appId),
      ).thenAnswer((_) async {});
      final result = await command.run();
      expect(result, ExitCode.success.code);
    });

    test('returns software error when app deletion fails', () async {
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => argResults['app-id']).thenReturn(appId);
      when(
        () => codePushClient.deleteApp(appId: appId),
      ).thenThrow(Exception());
      final result = await command.run();
      expect(result, ExitCode.software.code);
      verify(
        () => logger.err(any(that: contains('Unable to delete app'))),
      ).called(1);
    });
  });
}

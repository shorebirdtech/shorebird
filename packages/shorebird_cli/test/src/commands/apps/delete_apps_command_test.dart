import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockAccessCredentials extends Mock implements AccessCredentials {}

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockLogger extends Mock implements Logger {}

void main() {
  group('delete', () {
    const appId = 'example';
    final credentials = _MockAccessCredentials();

    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late Logger logger;
    late CodePushClient codePushClient;
    late DeleteAppCommand command;

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      logger = _MockLogger();
      codePushClient = _MockCodePushClient();
      command = DeleteAppCommand(
        auth: auth,
        buildCodePushClient: ({
          required http.Client httpClient,
          Uri? hostedUri,
        }) {
          return codePushClient;
        },
        logger: logger,
      )..testArgResults = argResults;

      when(() => auth.credentials).thenReturn(credentials);
      when(() => auth.client).thenReturn(httpClient);
    });

    test('returns correct description', () {
      expect(
        command.description,
        equals('Delete an existing app on Shorebird.'),
      );
    });

    test('returns no user error when not logged in', () async {
      when(() => auth.credentials).thenReturn(null);
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
      final error = Exception('oops');
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => argResults['app-id']).thenReturn(appId);
      when(() => codePushClient.deleteApp(appId: appId)).thenThrow(error);
      final result = await command.run();
      expect(result, ExitCode.software.code);
      verify(() => logger.err('$error')).called(1);
    });
  });
}

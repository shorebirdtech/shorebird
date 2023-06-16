import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockLogger extends Mock implements Logger {}

void main() {
  group(CreateAppCommand, () {
    const appId = 'app-id';
    const displayName = 'Example App';

    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late Logger logger;
    late CodePushClient codePushClient;
    late CreateAppCommand command;
    late CodePushClientWrapper codePushClientWrapper;


    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          loggerRef.overrideWith(() => logger)
        },
      );
    }

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      logger = _MockLogger();
      codePushClient = _MockCodePushClient();
      codePushClientWrapper = _MockCodePushClientWrapper();


      when(() => auth.client).thenReturn(httpClient);
      when(() => auth.isAuthenticated).thenReturn(true);

      command = runWithOverrides(
        () => CreateAppCommand(
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
      expect(command.description, equals('Create a new app on Shorebird.'));
    });

    test('returns no user error when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      final result = await runWithOverrides(command.run);
      expect(result, ExitCode.noUser.code);
    });

    test('prompts for app name when not provided', () async {
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(displayName);
      await runWithOverrides(command.run);
      verify(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).called(1);
      verify(
        () => codePushClientWrapper.createApp(displayName: displayName),
      ).called(1);
    });

    test('uses provided app name when provided', () async {
      when(() => argResults['app-name']).thenReturn(displayName);
      await runWithOverrides(command.run);
      verifyNever(() => logger.prompt(any()));
      verify(
        () => codePushClientWrapper.createApp(displayName: displayName),
      ).called(1);
    });

    test('returns success when app is created', () async {
      when(() => argResults['app-name']).thenReturn(displayName);
      when(
        () => codePushClientWrapper.createApp(displayName: displayName),
      ).thenAnswer((_) async => const App(id: appId, displayName: displayName));
      final result = await runWithOverrides(command.run);
      expect(result, ExitCode.success.code);
    });

    test('returns software error when app creation fails', () async {
      final error = Exception('oops');
      when(() => argResults['app-name']).thenReturn(displayName);
      when(
        () => codePushClientWrapper.createApp(displayName: displayName),
      ).thenThrow(error);
      final result = await runWithOverrides(command.run);
      expect(result, ExitCode.software.code);
      // verify(() => logger.err('$error')).called(1);
    });
  });
}

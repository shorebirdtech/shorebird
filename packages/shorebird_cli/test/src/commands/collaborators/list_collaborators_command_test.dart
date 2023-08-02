import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockLogger extends Mock implements Logger {}

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

void main() {
  group(ListCollaboratorsCommand, () {
    const appId = 'test-app-id';

    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late CodePushClient codePushClient;
    late Logger logger;
    late ShorebirdValidator shorebirdValidator;
    late ListCollaboratorsCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          loggerRef.overrideWith(() => logger),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = _MockArgResults();
      httpClient = _MockHttpClient();
      auth = _MockAuth();
      codePushClient = _MockCodePushClient();
      logger = _MockLogger();
      shorebirdValidator = _MockShorebirdValidator();

      when(() => argResults['app-id']).thenReturn(appId);
      when(() => auth.client).thenReturn(httpClient);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(
        () => ListCollaboratorsCommand(
          buildCodePushClient: ({
            required http.Client httpClient,
            Uri? hostedUri,
          }) {
            return codePushClient;
          },
        ),
      )..testArgResults = argResults;
    });

    test('name is correct', () {
      expect(command.name, equals('list'));
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

    test('exits when validation fails', () async {
      final exception = ValidationFailedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenThrow(exception);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(exception.exitCode.code)),
      );
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
        ),
      ).called(1);
    });

    test('returns ExitCode.usage when app id is missing.', () async {
      when(() => argResults['app-id']).thenReturn(null);
      expect(await runWithOverrides(command.run), ExitCode.usage.code);
    });

    test('returns ExitCode.software when unable to get collaborators',
        () async {
      when(
        () => codePushClient.getCollaborators(appId: any(named: 'appId')),
      ).thenThrow(Exception());
      expect(await runWithOverrides(command.run), ExitCode.software.code);
    });

    test('returns ExitCode.success when collaborators are empty', () async {
      when(
        () => codePushClient.getCollaborators(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(() => logger.info('(empty)')).called(1);
    });

    test('returns ExitCode.success when collaborators are not empty', () async {
      final collaborators = [
        const Collaborator(
          userId: 0,
          email: 'jane.doe@shorebird.dev',
          role: CollaboratorRole.admin,
        ),
        const Collaborator(
          userId: 1,
          email: 'john.doe@shorebird.dev',
          role: CollaboratorRole.developer,
        ),
      ];
      when(
        () => codePushClient.getCollaborators(appId: any(named: 'appId')),
      ).thenAnswer((_) async => collaborators);
      expect(await runWithOverrides(command.run), ExitCode.success.code);
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
┌────────────────────────┬───────────┐
│ Email                  │ Role      │
├────────────────────────┼───────────┤
│ jane.doe@shorebird.dev │ admin     │
├────────────────────────┼───────────┤
│ john.doe@shorebird.dev │ developer │
└────────────────────────┴───────────┘''',
        ),
      ).called(1);
    });
  });
}

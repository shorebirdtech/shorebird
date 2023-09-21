import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(ListCollaboratorsCommand, () {
    const appId = 'test-app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late CodePushClient codePushClient;
    late Logger logger;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ListCollaboratorsCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      codePushClient = MockCodePushClient();
      logger = MockLogger();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults['app-id']).thenReturn(appId);
      when(
        () => codePushClientWrapper.codePushClient,
      ).thenReturn(codePushClient);
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(ListCollaboratorsCommand.new)
        ..testArgResults = argResults;
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
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(null);
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

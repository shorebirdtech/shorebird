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
  group(AddCollaboratorsCommand, () {
    const appId = 'test-app-id';
    const email = 'jane.doe@shorebird.dev';
    const shorebirdYaml = ShorebirdYaml(appId: appId);

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late CodePushClient codePushClient;
    late Logger logger;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late AddCollaboratorsCommand command;

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
      progress = MockProgress();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults['app-id']).thenReturn(appId);
      when(() => argResults['email']).thenReturn(email);
      when(
        () => codePushClientWrapper.codePushClient,
      ).thenReturn(codePushClient);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(AddCollaboratorsCommand.new)
        ..testArgResults = argResults;
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

    test('returns ExitCode.success when user aborts', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(() => logger.info('Aborted.')).called(1);
      verifyNever(
        () => codePushClient.createCollaborator(
          appId: any(named: 'appId'),
          email: any(named: 'email'),
        ),
      );
    });

    test(
        '''exits with code 70 if user does not have permission to add collaborators''',
        () async {
      final error = CodePushForbiddenException(
        message: 'oops something went wrong',
      );
      when(
        () => codePushClient.createCollaborator(
          appId: any(named: 'appId'),
          email: any(named: 'email'),
        ),
      ).thenThrow(error);
      expect(await runWithOverrides(command.run), ExitCode.software.code);
      verify(() => logger.err('$error')).called(1);
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
      expect(await runWithOverrides(command.run), ExitCode.software.code);
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
      expect(await runWithOverrides(command.run), ExitCode.success.code);
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
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(() => logger.success('\n✅ New Collaborator Added!')).called(1);
    });
  });
}

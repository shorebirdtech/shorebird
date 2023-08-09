import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

void main() {
  group(DeleteCollaboratorsCommand, () {
    const appId = 'test-app-id';
    const email = 'jane.doe@shorebird.dev';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const collaborator = Collaborator(
      userId: 0,
      email: email,
      role: CollaboratorRole.admin,
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late CodePushClient codePushClient;
    late Logger logger;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late DeleteCollaboratorsCommand command;

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
      argResults = _MockArgResults();
      codePushClientWrapper = _MockCodePushClientWrapper();
      codePushClient = _MockCodePushClient();
      logger = _MockLogger();
      progress = _MockProgress();
      shorebirdEnv = _MockShorebirdEnv();
      shorebirdValidator = _MockShorebirdValidator();

      when(() => argResults['app-id']).thenReturn(appId);
      when(() => argResults['email']).thenReturn(email);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => codePushClientWrapper.codePushClient,
      ).thenReturn(codePushClient);
      when(
        () => codePushClient.getCollaborators(appId: any(named: 'appId')),
      ).thenAnswer((_) async => [collaborator]);
      when(
        () => codePushClient.deleteCollaborator(
          appId: any(named: 'appId'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((_) async {});
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(DeleteCollaboratorsCommand.new)
        ..testArgResults = argResults;
    });

    test('description is correct', () {
      expect(
        command.description,
        equals('Delete an existing collaborator from a Shorebird app.'),
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
      verifyNever(
        () => codePushClient.deleteCollaborator(
          appId: any(named: 'appId'),
          userId: any(named: 'userId'),
        ),
      );
      verify(() => logger.info('Aborted.')).called(1);
    });

    test(
        'returns ExitCode.software '
        'when fetching collaborators fails', () async {
      const error = 'oops something went wrong';
      when(
        () => codePushClient.getCollaborators(appId: any(named: 'appId')),
      ).thenThrow(error);
      expect(await runWithOverrides(command.run), ExitCode.software.code);
      verify(() => logger.err(error)).called(1);
    });

    test('returns ExitCode.software when collaborator does not exist',
        () async {
      when(
        () => codePushClient.getCollaborators(appId: any(named: 'appId')),
      ).thenAnswer((_) async => []);
      expect(await runWithOverrides(command.run), ExitCode.software.code);
      verify(
        () => logger.err(
          any(
            that: contains(
              'Could not find a collaborator with the email "$email".',
            ),
          ),
        ),
      ).called(1);
    });

    test(
        'returns ExitCode.software '
        'when deleting a collaborator fails', () async {
      const error = 'oops something went wrong';
      when(
        () => codePushClient.deleteCollaborator(
          appId: any(named: 'appId'),
          userId: any(named: 'userId'),
        ),
      ).thenThrow(error);
      expect(await runWithOverrides(command.run), ExitCode.software.code);
      verify(() => logger.err(error)).called(1);
    });

    test('prompts for email when not provided', () async {
      when(() => argResults['email']).thenReturn(null);
      when(() => logger.prompt(any())).thenReturn(email);
      when(
        () => codePushClient.deleteCollaborator(
          appId: any(named: 'appId'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((_) async => collaborator);
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(
        () => logger.prompt(
          '''${lightGreen.wrap('?')} What is the email of the collaborator you would like to delete?''',
        ),
      ).called(1);
      verify(
        () => codePushClient.deleteCollaborator(
          appId: appId,
          userId: collaborator.userId,
        ),
      ).called(1);
    });

    test('uses app-id from shorebird.yaml if one exists', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      File(
        p.join(tempDir.path, 'shorebird.yaml'),
      ).writeAsStringSync('app_id: $appId');
      when(() => argResults['app-id']).thenReturn(null);
      when(
        () => codePushClient.deleteCollaborator(
          appId: any(named: 'appId'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((_) async {});
      final result = await IOOverrides.runZoned(
        () => runWithOverrides(command.run),
        getCurrentDirectory: () => tempDir,
      );
      expect(result, ExitCode.success.code);
      verify(() => logger.success('\n✅ Collaborator Deleted!')).called(1);
      verify(
        () => codePushClient.deleteCollaborator(
          appId: appId,
          userId: collaborator.userId,
        ),
      ).called(1);
    });

    test('returns ExitCode.success on success', () async {
      when(
        () => codePushClient.deleteCollaborator(
          appId: any(named: 'appId'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((_) async {});
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(() => logger.success('\n✅ Collaborator Deleted!')).called(1);
    });
  });
}

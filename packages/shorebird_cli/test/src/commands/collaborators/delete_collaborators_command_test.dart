import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClient extends Mock implements CodePushClient {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

void main() {
  group(DeleteCollaboratorsCommand, () {
    const appId = 'test-app-id';
    const email = 'jane.doe@shorebird.dev';
    const collaborator = Collaborator(userId: 0, email: email);

    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late CodePushClient codePushClient;
    late Logger logger;
    late Progress progress;
    late DeleteCollaboratorsCommand command;

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
      codePushClient = _MockCodePushClient();
      logger = _MockLogger();
      progress = _MockProgress();

      when(() => argResults['app-id']).thenReturn(appId);
      when(() => argResults['email']).thenReturn(email);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => codePushClient.getCollaborators(appId: any(named: 'appId')),
      ).thenAnswer((_) async => [collaborator]);
      when(
        () => codePushClient.deleteCollaborator(
          appId: any(named: 'appId'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(
        () => DeleteCollaboratorsCommand(
          buildCodePushClient: ({
            required http.Client httpClient,
            Uri? hostedUri,
          }) {
            return codePushClient;
          },
        ),
      )..testArgResults = argResults;
    });

    test('description is correct', () {
      expect(
        command.description,
        equals('Delete an existing collaborator from a Shorebird app.'),
      );
    });

    test('returns ExitCode.noUser when not logged in', () async {
      when(() => auth.isAuthenticated).thenReturn(false);
      expect(await runWithOverrides(command.run), ExitCode.noUser.code);
    });

    test('returns ExitCode.usage when app id is missing.', () async {
      when(() => argResults['app-id']).thenReturn(null);
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

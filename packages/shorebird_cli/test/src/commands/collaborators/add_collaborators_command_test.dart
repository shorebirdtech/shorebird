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

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

void main() {
  group(AddCollaboratorsCommand, () {
    const appId = 'test-app-id';
    const email = 'jane.doe@shorebird.dev';

    late ArgResults argResults;
    late http.Client httpClient;
    late Auth auth;
    late CodePushClient codePushClient;
    late Logger logger;
    late Progress progress;
    late ShorebirdValidator shorebirdValidator;
    late AddCollaboratorsCommand command;

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
      progress = _MockProgress();
      shorebirdValidator = _MockShorebirdValidator();

      when(() => argResults['app-id']).thenReturn(appId);
      when(() => argResults['email']).thenReturn(email);
      when(() => auth.client).thenReturn(httpClient);
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(
        () => AddCollaboratorsCommand(
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

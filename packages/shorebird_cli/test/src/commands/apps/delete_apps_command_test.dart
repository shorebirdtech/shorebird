import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
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

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

void main() {
  group(DeleteAppCommand, () {
    const appId = 'example';

    late ArgResults argResults;
    late Logger logger;
    late CodePushClientWrapper codePushClientWrapper;
    late CodePushClient codePushClient;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late DeleteAppCommand command;

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
      logger = _MockLogger();
      codePushClientWrapper = _MockCodePushClientWrapper();
      codePushClient = _MockCodePushClient();
      shorebirdEnv = _MockShorebirdEnv();
      shorebirdValidator = _MockShorebirdValidator();

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.codePushClient,
      ).thenReturn(codePushClient);

      command = runWithOverrides(DeleteAppCommand.new)
        ..testArgResults = argResults;
    });

    test('has a description', () {
      expect(
        command.description,
        equals('Delete an existing app on Shorebird.'),
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

    test('prompts for app-id when not provided', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      when(() => logger.prompt(any())).thenReturn(appId);
      await runWithOverrides(command.run);
      verify(() => logger.prompt(any())).called(1);
    });

    test('uses provided app-id when provided', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      when(() => argResults['app-id']).thenReturn(appId);
      await runWithOverrides(command.run);
      verifyNever(() => logger.prompt(any()));
    });

    test('aborts when user does not confirm', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      when(() => argResults['app-id']).thenReturn(appId);
      final result = await runWithOverrides(command.run);
      expect(result, ExitCode.success.code);
      verifyNever(() => codePushClient.deleteApp(appId: appId));
      verify(() => logger.info('Aborted.')).called(1);
    });

    test('does not prompt for confirmation when force flag is provided',
        () async {
      when(() => argResults['app-id']).thenReturn(appId);
      when(() => argResults['force']).thenReturn(true);
      when(
        () => codePushClient.deleteApp(appId: appId),
      ).thenAnswer((_) async {});
      final result = await runWithOverrides(command.run);
      expect(result, ExitCode.success.code);
      verify(() => codePushClient.deleteApp(appId: appId));
      verifyNever(() => logger.confirm(any()));
    });

    test('returns success when app is deleted', () async {
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => argResults['app-id']).thenReturn(appId);
      when(
        () => codePushClient.deleteApp(appId: appId),
      ).thenAnswer((_) async {});
      final result = await runWithOverrides(command.run);
      expect(result, ExitCode.success.code);
    });

    test('returns software error when app deletion fails', () async {
      final error = Exception('oops');
      when(() => logger.confirm(any())).thenReturn(true);
      when(() => argResults['app-id']).thenReturn(appId);
      when(() => codePushClient.deleteApp(appId: appId)).thenThrow(error);
      final result = await runWithOverrides(command.run);
      expect(result, ExitCode.software.code);
      verify(() => logger.err('$error')).called(1);
    });
  });
}

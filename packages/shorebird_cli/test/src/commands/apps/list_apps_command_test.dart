import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements Auth {}

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockLogger extends Mock implements Logger {}

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

void main() {
  group(ListAppsCommand, () {
    late Auth auth;
    late CodePushClientWrapper codePushClientWrapper;
    late Logger logger;
    late ShorebirdValidator shorebirdValidator;
    late ListAppsCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          loggerRef.overrideWith(() => logger),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      auth = _MockAuth();
      codePushClientWrapper = _MockCodePushClientWrapper();
      logger = _MockLogger();
      shorebirdValidator = _MockShorebirdValidator();
      command = ListAppsCommand();

      when(() => auth.isAuthenticated).thenReturn(true);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
    });

    test('has a description', () {
      expect(command.description, equals('List all apps using Shorebird.'));
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

    test('returns ExitCode.success when apps are empty', () async {
      when(codePushClientWrapper.getApps).thenAnswer((_) async => []);
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(() => logger.info('(empty)')).called(1);
    });

    test('returns ExitCode.success when apps are not empty', () async {
      final apps = [
        const AppMetadata(
          appId: '30370f27-dbf1-4673-8b20-fb096e38dffa',
          displayName: 'Shorebird Counter',
          latestReleaseVersion: '1.0.0',
          latestPatchNumber: 1,
        ),
        const AppMetadata(
          appId: '05b45471-a5f3-48cd-b26a-da29d95914a7',
          displayName: 'Shorebird Clock',
        ),
      ];
      when(codePushClientWrapper.getApps).thenAnswer((_) async => apps);
      expect(await runWithOverrides(command.run), ExitCode.success.code);
      verify(
        () => logger.info(
          '''
┌───────────────────┬──────────────────────────────────────┬─────────┬───────┐
│ Name              │ ID                                   │ Release │ Patch │
├───────────────────┼──────────────────────────────────────┼─────────┼───────┤
│ Shorebird Counter │ 30370f27-dbf1-4673-8b20-fb096e38dffa │ 1.0.0   │ 1     │
├───────────────────┼──────────────────────────────────────┼─────────┼───────┤
│ Shorebird Clock   │ 05b45471-a5f3-48cd-b26a-da29d95914a7 │ --      │ --    │
└───────────────────┴──────────────────────────────────────┴─────────┴───────┘''',
        ),
      ).called(1);
    });
  });
}

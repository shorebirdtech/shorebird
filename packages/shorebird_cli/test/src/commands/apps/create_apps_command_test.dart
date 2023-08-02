import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockCodePushClientWrapper extends Mock
    implements CodePushClientWrapper {}

class _MockLogger extends Mock implements Logger {}

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

void main() {
  group(CreateAppCommand, () {
    const appId = 'app-id';
    const appName = 'Example App';

    late ArgResults argResults;
    late Logger logger;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdValidator shorebirdValidator;
    late CreateAppCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          loggerRef.overrideWith(() => logger),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = _MockArgResults();
      logger = _MockLogger();
      codePushClientWrapper = _MockCodePushClientWrapper();
      shorebirdValidator = _MockShorebirdValidator();

      when(() => argResults['app-name']).thenReturn(appName);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.createApp(appName: appName),
      ).thenAnswer((_) async => const App(id: appId, displayName: appName));

      command = runWithOverrides(CreateAppCommand.new)
        ..testArgResults = argResults;
    });

    test('has a description', () {
      expect(command.description, equals('Create a new app on Shorebird.'));
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

    test('calls createApp with no app-name when not provided', () async {
      when(() => argResults['app-name']).thenReturn(null);
      await runWithOverrides(command.run);
      verify(() => codePushClientWrapper.createApp()).called(1);
    });

    test('uses provided app name when provided', () async {
      await runWithOverrides(command.run);
      verify(
        () => codePushClientWrapper.createApp(appName: appName),
      ).called(1);
    });

    test('returns success when app is created', () async {
      final result = await runWithOverrides(command.run);
      expect(result, ExitCode.success.code);
    });

    test('returns software error when app creation fails', () async {
      final error = Exception('oops');
      when(
        () => codePushClientWrapper.createApp(appName: appName),
      ).thenThrow(error);
      final result = await runWithOverrides(command.run);
      expect(result, ExitCode.software.code);
      verify(() => logger.err('$error')).called(1);
    });
  });
}

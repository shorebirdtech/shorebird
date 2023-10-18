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
  group(ListReleasesCommand, () {
    const appId = 'test-app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late CodePushClient codePushClient;
    late Logger logger;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ListReleasesCommand command;

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

      when(
        () => codePushClientWrapper.codePushClient,
      ).thenReturn(codePushClient);
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(ListReleasesCommand.new)
        ..testArgResults = argResults;
    });

    test('description is correct', () {
      expect(command.description, equals('List all releases for this app.'));
    });

    test('exits when validation fails', () async {
      final exception = ValidationFailedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenThrow(exception);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(exception.exitCode.code)),
      );
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
          checkShorebirdInitialized: true,
        ),
      ).called(1);
    });

    test('returns ExitCode.software when unable to get releases', () async {
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenThrow(Exception());

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.software.code);
    });

    test('returns ExitCode.success when releases is empty', () async {
      when(
        () => codePushClient.getReleases(appId: appId),
      ).thenAnswer((_) async => []);

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.success.code);
      verify(() => logger.info('(empty)')).called(1);
    });

    test('uses correct app_id when flavor is specified', () async {
      const flavor = 'development';
      when(() => argResults['flavor']).thenReturn(flavor);
      const shorebirdYaml = ShorebirdYaml(
        appId: 'productionAppId',
        flavors: {flavor: appId},
      );
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(() => codePushClient.getReleases(appId: appId)).thenAnswer(
        (_) async => [
          Release(
            id: 1,
            appId: appId,
            version: '1.0.0',
            flutterRevision: flutterRevision,
            displayName: 'v1.0.0 (dev)',
            platformStatuses: {ReleasePlatform.ios: ReleaseStatus.draft},
            createdAt: DateTime(2023),
            updatedAt: DateTime(2023),
          ),
        ],
      );

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.success.code);
      verify(
        () => logger.info('''
┌─────────┬──────────────┐
│ Version │ Name         │
├─────────┼──────────────┤
│ 1.0.0   │ v1.0.0 (dev) │
└─────────┴──────────────┘'''),
      ).called(1);
    });

    test('returns ExitCode.success and prints releases when releases exist',
        () async {
      when(() => codePushClient.getReleases(appId: appId)).thenAnswer(
        (_) async => [
          Release(
            id: 1,
            appId: appId,
            version: '1.0.1',
            flutterRevision: flutterRevision,
            displayName: 'First',
            platformStatuses: {ReleasePlatform.ios: ReleaseStatus.active},
            createdAt: DateTime(2023),
            updatedAt: DateTime(2023),
          ),
          Release(
            id: 1,
            appId: appId,
            version: '1.0.2',
            flutterRevision: flutterRevision,
            displayName: null,
            platformStatuses: {ReleasePlatform.ios: ReleaseStatus.draft},
            createdAt: DateTime(2023),
            updatedAt: DateTime(2023),
          ),
        ],
      );

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.success.code);
      verify(
        () => logger.info('''
┌─────────┬───────┐
│ Version │ Name  │
├─────────┼───────┤
│ 1.0.1   │ First │
├─────────┼───────┤
│ 1.0.2   │ --    │
└─────────┴───────┘'''),
      ).called(1);
    });
  });
}

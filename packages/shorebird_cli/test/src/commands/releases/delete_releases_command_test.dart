import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/releases/releases.dart';
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
  group(DeleteReleasesCommand, () {
    const appId = 'test-app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const releaseId = 3;
    const versionNumber = '1.0.0';

    late ArgResults argResults;
    late Logger logger;
    late CodePushClientWrapper codePushClientWrapper;
    late CodePushClient codePushClient;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late DeleteReleasesCommand command;

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
      progress = _MockProgress();
      shorebirdEnv = _MockShorebirdEnv();
      shorebirdValidator = _MockShorebirdValidator();

      when(() => argResults['version']).thenReturn(versionNumber);
      when(
        () => codePushClientWrapper.codePushClient,
      ).thenReturn(codePushClient);
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(() => codePushClient.getReleases(appId: any(named: 'appId')))
          .thenAnswer(
        (_) async => [
          const Release(
            id: 1,
            appId: appId,
            version: '0.1.0',
            flutterRevision: flutterRevision,
            displayName: null,
            platformStatuses: {ReleasePlatform.android: ReleaseStatus.active},
          ),
          const Release(
            id: 2,
            appId: appId,
            version: '0.1.1',
            flutterRevision: flutterRevision,
            displayName: null,
            platformStatuses: {},
          ),
          const Release(
            id: releaseId,
            appId: appId,
            version: versionNumber,
            flutterRevision: flutterRevision,
            displayName: null,
            platformStatuses: {ReleasePlatform.android: ReleaseStatus.active},
          ),
        ],
      );

      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(DeleteReleasesCommand.new)
        ..testArgResults = argResults;
    });

    test('returns correct description', () {
      expect(
        command.description,
        'Delete the specified release version.',
      );
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

    test('prompts for version when not provided', () async {
      when(() => argResults['version']).thenReturn(null);
      when(() => logger.prompt(any())).thenReturn(versionNumber);

      await runWithOverrides(command.run);

      verify(
        () => logger.prompt(
          any(that: contains('Which version would you like to delete?')),
        ),
      ).called(1);
    });

    test('does not prompt for version if user provides it with a flag',
        () async {
      await runWithOverrides(command.run);
      verifyNever(() => logger.prompt(any()));
    });

    test('returns software exit code if get releases request fails', () async {
      when(
        () => codePushClient.getReleases(appId: any(named: 'appId')),
      ).thenThrow(Exception('oops'));

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.software.code);
    });

    test('aborts when user does not confirm', () async {
      when(() => logger.confirm(any())).thenReturn(false);

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.success.code);
      verifyNever(
        () => codePushClient.deleteRelease(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      );
      verify(() => logger.info('Aborted.')).called(1);
    });

    test('returns software error when release is not found', () async {
      when(() => argResults['version']).thenReturn('asdf');

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.software.code);
      verify(() => logger.err('No release found for version "asdf"')).called(1);
      verifyNever(
        () => codePushClient.deleteRelease(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      );
    });

    test('returns software error when delete release fails', () async {
      when(
        () => codePushClient.deleteRelease(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      ).thenThrow(Exception('oops'));

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.software.code);
      verify(() => progress.fail(any(that: contains('oops')))).called(1);
      verify(
        () => codePushClient.deleteRelease(appId: appId, releaseId: releaseId),
      ).called(1);
    });

    test('returns success when release is deleted', () async {
      when(
        () => codePushClient.deleteRelease(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      ).thenAnswer((_) async {});

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.success.code);
      verify(
        () => codePushClient.deleteRelease(appId: appId, releaseId: releaseId),
      ).called(1);
      verify(
        () => progress.complete('Deleted release $versionNumber.'),
      ).called(1);
    });

    test('uses correct app_id when flavor is specified', () async {
      const flavor = 'development';
      when(() => argResults['flavor']).thenReturn(flavor);
      const shorebirdYaml = ShorebirdYaml(
        appId: 'productionAppId',
        flavors: {flavor: appId},
      );
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(
        () => codePushClient.deleteRelease(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      ).thenAnswer((_) async {});

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.success.code);
      verify(() => codePushClient.getReleases(appId: appId)).called(1);
      verify(
        () => codePushClient.deleteRelease(appId: appId, releaseId: releaseId),
      ).called(1);
      verify(
        () => progress.complete('Deleted release $versionNumber.'),
      ).called(1);
    });
  });
}

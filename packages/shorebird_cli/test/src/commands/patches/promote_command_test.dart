import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patches/patches.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../mocks.dart';

void main() {
  group(PromoteCommand, () {
    const appId = 'app-id';
    const releaseVersion = '1.0.0';
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const flutterVersion = '3.22.0';
    const releasePlatform = ReleasePlatform.android;
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final stableChannel = Channel(
      id: 0,
      appId: appId,
      name: DeploymentTrack.stable.channel,
    );
    final release = Release(
      id: 0,
      appId: appId,
      version: releaseVersion,
      flutterRevision: flutterRevision,
      flutterVersion: flutterVersion,
      displayName: '1.2.3+1',
      platformStatuses: const {releasePlatform: ReleaseStatus.active},
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );
    final patch = ReleasePatch(
      id: 0,
      number: 1,
      channel: DeploymentTrack.staging.channel,
      isRolledBack: false,
      artifacts: const [],
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;

    late PromoteCommand command;

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

    setUpAll(() {
      registerFallbackValue(FakeChannel());
    });

    setUp(() {
      argResults = MockArgResults();
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();

      when(() => argResults.wasParsed(any())).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['release-version']).thenReturn('1.0.0');
      when(() => argResults['patch-number']).thenReturn('1');

      when(
        () => codePushClientWrapper.getRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
      when(
        () => codePushClientWrapper.getReleasePatches(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      ).thenAnswer((_) async => [patch]);
      when(
        () => codePushClientWrapper.maybeGetChannel(
          appId: any(named: 'appId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => stableChannel);
      when(
        () => codePushClientWrapper.promotePatch(
          appId: any(named: 'appId'),
          patchId: any(named: 'patchId'),
          channel: any(named: 'channel'),
        ),
      ).thenAnswer((_) async => {});

      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async {});

      command = PromoteCommand()..testArgResults = argResults;
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    group('when validation fails', () {
      test('exits with exit code from validation error', () async {
        final exception = ShorebirdNotInitializedException();
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
            checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          ),
        ).thenThrow(exception);

        final result = await runWithOverrides(command.run);
        expect(result, equals(exception.exitCode.code));
        verify(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: true,
            checkShorebirdInitialized: true,
          ),
        ).called(1);
      });
    });

    group('when an invalid patch number is provided', () {
      setUp(() {
        when(() => argResults['patch-number']).thenReturn('5');
      });

      test('should log an error', () async {
        await runWithOverrides(() async {
          final result = await command.run();

          expect(result, equals(ExitCode.usage.code));
          verify(() => logger.err('No patch found with number 5')).called(1);
          verify(() => logger.info('Available patches: 1')).called(1);
        });
      });
    });

    group('when patch is already in production', () {
      setUp(() {
        final prodPatch = ReleasePatch(
          id: 0,
          number: 1,
          channel: DeploymentTrack.stable.channel,
          isRolledBack: false,
          artifacts: const [],
        );
        when(
          () => codePushClientWrapper.getReleasePatches(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
          ),
        ).thenAnswer((_) async => [prodPatch]);
      });

      test(
        'tells user patch is already in prod, exits with usage code',
        () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.usage.code));
          verify(() => logger.err('Patch 1 is already live')).called(1);
        },
      );
    });

    group('when app has no stable channel', () {
      setUp(() {
        when(
          () => codePushClientWrapper.maybeGetChannel(
            appId: any(named: 'appId'),
            name: DeploymentTrack.stable.channel,
          ),
        ).thenAnswer((_) async => null);
      });

      test('exits with software error code', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.software.code));
      });
    });

    group('when patch is successfully promoted', () {
      test('exits with success code', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => codePushClientWrapper.promotePatch(
            appId: appId,
            patchId: patch.id,
            channel: stableChannel,
          ),
        );
        verify(
          () => logger.success('Patch 1 is now live for release 1.0.0!'),
        ).called(1);
      });
    });
  });
}

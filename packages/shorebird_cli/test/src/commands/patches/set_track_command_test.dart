import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patches/set_track_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../mocks.dart';

void main() {
  group(SetTrackCommand, () {
    const appId = 'app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const patchNumberArg = 1;
    final release = Release(
      id: 0,
      appId: appId,
      version: '1.0.0',
      flutterRevision: 'flutter-revision',
      flutterVersion: 'flutter-version',
      displayName: '1.0.0',
      platformStatuses: const {ReleasePlatform.android: ReleaseStatus.active},
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    const patch = ReleasePatch(
      id: 0,
      number: patchNumberArg,
      channel: 'stable',
      isRolledBack: false,
      artifacts: [],
    );
    const newChannel = Channel(
      id: 1,
      appId: appId,
      name: 'new-channel',
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;

    late SetTrackCommand command;

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
      when(() => argResults['release']).thenReturn('1.0.0');
      when(
        () => argResults['patch'],
      ).thenReturn(patchNumberArg.toString());
      when(() => argResults['track']).thenReturn(newChannel.name);

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async => {});
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);

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
      ).thenAnswer((_) async => newChannel);
      when(
        () => codePushClientWrapper.createChannel(
          appId: any(named: 'appId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => newChannel);
      when(
        () => codePushClientWrapper.promotePatch(
          appId: any(named: 'appId'),
          patchId: any(named: 'patchId'),
          channel: any(named: 'channel'),
        ),
      ).thenAnswer((_) async => {});

      command = SetTrackCommand()..testArgResults = argResults;
    });

    test('name is correct', () {
      expect(command.name, 'set-track');
    });

    test('description is correct', () {
      expect(command.description, 'Sets the track of a patch');
    });

    group('when validation fails', () {
      final exception = ShorebirdNotInitializedException();
      setUp(() {
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
            checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          ),
        ).thenThrow(exception);
      });

      test('exits with exit code from validation error', () async {
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

    group('when release has no patches', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getReleasePatches(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
          ),
        ).thenAnswer((_) async => []);
      });

      test('exits with code 70', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err('No patches found for release 1.0.0'),
        ).called(1);
      });
    });

    group('when no patch matching arg values is found', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getReleasePatches(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
          ),
        ).thenAnswer(
          (_) async => [
            const ReleasePatch(
              id: 1,
              number: patchNumberArg + 1,
              channel: 'stable',
              isRolledBack: false,
              artifacts: [],
            ),
          ],
        );
      });

      test('exits with code 70', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err('No patch found with number 1'),
        ).called(1);
      });
    });

    group('when no channel with the specified name is found', () {
      setUp(() {
        when(
          () => codePushClientWrapper.maybeGetChannel(
            appId: any(named: 'appId'),
            name: any(named: 'name'),
          ),
        ).thenAnswer((_) async => null);
        when(() => logger.confirm(any())).thenReturn(false);
      });

      test('prompts to create the channel', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.confirm(
            '''No channel named ${lightCyan.wrap(newChannel.name)} found. Do you want to create it?''',
          ),
        ).called(1);
      });

      group('when user confirms to create the channel', () {
        setUp(() {
          when(() => logger.confirm(any())).thenReturn(true);
        });

        test('creates the channel', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verify(
            () => codePushClientWrapper.createChannel(
              appId: any(named: 'appId'),
              name: any(named: 'name'),
            ),
          ).called(1);
        });
      });

      group('when user declines to create the channel', () {
        setUp(() {
          when(() => logger.confirm(any())).thenReturn(false);
        });

        test('exits with code 70', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verifyNever(
            () => codePushClientWrapper.createChannel(
              appId: any(named: 'appId'),
              name: any(named: 'name'),
            ),
          );
        });
      });
    });

    group('when patch is already in the specified channel', () {
      setUp(() {
        final patch = ReleasePatch(
          id: 0,
          number: patchNumberArg,
          channel: newChannel.name,
          isRolledBack: false,
          artifacts: const [],
        );
        when(
          () => codePushClientWrapper.getReleasePatches(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
          ),
        ).thenAnswer((_) async => [patch]);
      });

      test('exits with code 70', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            'Patch ${patch.number} is already in channel ${newChannel.name}',
          ),
        ).called(1);
      });
    });

    group('when patch is not in the specified channel', () {
      test('promotes the patch to the specified channel', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => codePushClientWrapper.promotePatch(
            appId: appId,
            patchId: patch.id,
            channel: newChannel,
          ),
        ).called(1);
        verify(
          () => logger.success(
            '''Patch ${patch.number} on release ${release.version} is now in channel ${newChannel.name}!''',
          ),
        ).called(1);
      });
    });
  });
}

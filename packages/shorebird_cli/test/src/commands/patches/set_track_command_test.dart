import 'dart:convert';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patches/set_track_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  group(SetTrackCommand, () {
    const appId = 'app-id';
    const releaseVersion = '1.0.0';
    const patchNumber = 1;
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final release = Release(
      id: 0,
      appId: appId,
      version: releaseVersion,
      flutterRevision: 'flutter-revision',
      flutterVersion: 'flutter-version',
      displayName: releaseVersion,
      platformStatuses: const {ReleasePlatform.android: ReleaseStatus.active},
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    const patch = ReleasePatch(
      id: 0,
      number: patchNumber,
      channel: 'stable',
      isRolledBack: false,
      artifacts: [],
    );
    const targetChannel = Channel(
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
          isJsonModeRef.overrideWith(() => false),
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
      when(() => argResults['app-id']).thenReturn(null);
      when(() => argResults['flavor']).thenReturn(null);
      when(() => argResults['release']).thenReturn(releaseVersion);
      when(() => argResults['patch']).thenReturn(patchNumber.toString());
      when(() => argResults['track']).thenReturn(targetChannel.name);

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
      ).thenAnswer((_) async => targetChannel);
      when(
        () => codePushClientWrapper.createChannel(
          appId: any(named: 'appId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => targetChannel);
      when(
        () => codePushClientWrapper.promotePatch(
          appId: any(named: 'appId'),
          patchId: any(named: 'patchId'),
          channel: any(named: 'channel'),
        ),
      ).thenAnswer((_) async => {});

      command = runWithOverrides(SetTrackCommand.new)
        ..testArgResults = argResults;
    });

    test('name is correct', () {
      expect(command.name, 'set-track');
    });

    test('has correct description', () {
      expect(command.description, startsWith('Sets the track of a patch.'));
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
      });
    });

    group('when --app-id is provided', () {
      setUp(() {
        when(() => argResults['app-id']).thenReturn('explicit-app-id');
        when(
          () => codePushClientWrapper.getRelease(
            appId: 'explicit-app-id',
            releaseVersion: any(named: 'releaseVersion'),
          ),
        ).thenAnswer((_) async => release);
      });

      test('does not require shorebird to be initialized', () async {
        await runWithOverrides(command.run);
        verify(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: true,
          ),
        ).called(1);
      });

      test('uses the explicit app id', () async {
        await runWithOverrides(command.run);
        verify(
          () => codePushClientWrapper.getRelease(
            appId: 'explicit-app-id',
            releaseVersion: releaseVersion,
          ),
        ).called(1);
      });
    });

    group('when --app-id is not provided', () {
      test('requires shorebird to be initialized', () async {
        await runWithOverrides(command.run);
        verify(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: true,
            checkShorebirdInitialized: true,
          ),
        ).called(1);
      });
    });

    group('when track name is empty', () {
      setUp(() {
        when(() => argResults['track']).thenReturn('');
      });

      test('exits with usage error', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err('Track name must be between 1 and 128 characters.'),
        ).called(1);
      });
    });

    group('when track name exceeds max length', () {
      setUp(() {
        when(() => argResults['track']).thenReturn('a' * 129);
      });

      test('exits with usage error', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err('Track name must be between 1 and 128 characters.'),
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

      test('exits with usage error', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err('No patches found for release $releaseVersion'),
        ).called(1);
      });
    });

    group('when no matching patch is found', () {
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
              number: patchNumber + 1,
              channel: 'stable',
              isRolledBack: false,
              artifacts: [],
            ),
          ],
        );
      });

      test('exits with usage error', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err('No patch found with number $patchNumber'),
        ).called(1);
      });
    });

    group('when patch is already in the specified channel', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getReleasePatches(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
          ),
        ).thenAnswer(
          (_) async => [
            ReleasePatch(
              id: 0,
              number: patchNumber,
              channel: targetChannel.name,
              isRolledBack: false,
              artifacts: const [],
            ),
          ],
        );
      });

      test('exits with usage error', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            'Patch $patchNumber is already in channel ${targetChannel.name}',
          ),
        ).called(1);
      });
    });

    group('when channel does not exist', () {
      setUp(() {
        when(
          () => codePushClientWrapper.maybeGetChannel(
            appId: any(named: 'appId'),
            name: any(named: 'name'),
          ),
        ).thenAnswer((_) async => null);
        when(
          () => logger.confirm(any(), hint: any(named: 'hint')),
        ).thenReturn(false);
      });

      test('prompts to create the channel', () async {
        await runWithOverrides(command.run);
        verify(
          () => logger.confirm(
            any(that: contains(targetChannel.name)),
            hint: any(named: 'hint'),
          ),
        ).called(1);
      });

      group('when user confirms channel creation', () {
        setUp(() {
          when(
            () => logger.confirm(any(), hint: any(named: 'hint')),
          ).thenReturn(true);
        });

        test('creates the channel and promotes the patch', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verify(
            () => codePushClientWrapper.createChannel(
              appId: appId,
              name: targetChannel.name,
            ),
          ).called(1);
        });
      });

      group('when user declines channel creation', () {
        test('exits with success without promoting', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verifyNever(
            () => codePushClientWrapper.createChannel(
              appId: any(named: 'appId'),
              name: any(named: 'name'),
            ),
          );
          verifyNever(
            () => codePushClientWrapper.promotePatch(
              appId: any(named: 'appId'),
              patchId: any(named: 'patchId'),
              channel: any(named: 'channel'),
            ),
          );
        });
      });
    });

    group('when patch is promoted successfully', () {
      test('promotes patch and logs success', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => codePushClientWrapper.promotePatch(
            appId: appId,
            patchId: patch.id,
            channel: targetChannel,
          ),
        ).called(1);
        verify(
          () => logger.success(
            'Patch $patchNumber on release $releaseVersion '
            'is now in channel ${targetChannel.name}!',
          ),
        ).called(1);
      });
    });

    group('--json', () {
      R runJsonMode<R>(R Function() body) {
        return runScoped(
          body,
          values: {
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
            isJsonModeRef.overrideWith(() => true),
            loggerRef.overrideWith(() => logger),
            shorebirdEnvRef.overrideWith(() => shorebirdEnv),
            shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          },
        );
      }

      test(
        'emits JSON success with release_version, patch_number, track',
        () async {
          final captured = <String>[];
          final result = await captureStdout(
            () => runJsonMode(command.run),
            captured: captured,
          );
          expect(result, equals(ExitCode.success.code));
          expect(captured, hasLength(1));
          final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
          expect(decoded['status'], 'success');
          final data = decoded['data'] as Map<String, dynamic>;
          expect(data['release_version'], releaseVersion);
          expect(data['patch_number'], patchNumber);
          expect(data['track'], targetChannel.name);
        },
      );

      group('when channel does not exist', () {
        setUp(() {
          when(
            () => codePushClientWrapper.maybeGetChannel(
              appId: any(named: 'appId'),
              name: any(named: 'name'),
            ),
          ).thenAnswer((_) async => null);
        });

        test('emits interactive_prompt_required error', () async {
          final captured = <String>[];
          final result = await captureStdout(
            () => runJsonMode(command.run),
            captured: captured,
          );
          expect(result, equals(ExitCode.usage.code));
          expect(captured, hasLength(1));
          final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
          expect(decoded['status'], 'error');
          expect(
            (decoded['error'] as Map<String, dynamic>)['code'],
            'interactive_prompt_required',
          );
        });
      });

      group('when patch is not found', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleasePatches(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
            ),
          ).thenAnswer((_) async => []);
        });

        test('emits JSON error envelope', () async {
          final captured = <String>[];
          final result = await captureStdout(
            () => runJsonMode(command.run),
            captured: captured,
          );
          expect(result, equals(ExitCode.usage.code));
          final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
          expect(decoded['status'], 'error');
          expect(
            (decoded['error'] as Map<String, dynamic>)['code'],
            'usage_error',
          );
        });
      });
    });
  });
}

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patches/rollout_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/rollout_percentage.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(RolloutCommand, () {
    const appId = 'app-id';
    const releaseVersion = '1.0.0';
    const patchNumber = 1;
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final release = Release(
      id: 7,
      appId: appId,
      version: releaseVersion,
      flutterRevision: 'flutter-revision',
      flutterVersion: 'flutter-version',
      displayName: releaseVersion,
      platforms: const {
        ReleasePlatform.android: ReleasePlatformDetails(
          status: ReleaseStatus.active,
        ),
      },
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    const patch = ReleasePatch(
      id: 42,
      number: patchNumber,
      channel: 'stable',
      isRolledBack: false,
      artifacts: [],
      rolloutPercentage: 10,
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late RolloutCommand command;

    R runWithOverrides<R>(R Function() body, {bool jsonMode = false}) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => jsonMode),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    Future<({int exitCode, Map<String, dynamic> json})> runJson() =>
        captureJson(() => runWithOverrides(command.run, jsonMode: true));

    void stubPatches(List<ReleasePatch> patches) {
      when(
        () => codePushClientWrapper.getReleasePatches(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      ).thenAnswer((_) async => patches);
    }

    void verifyNoRolloutRequest() {
      verifyNever(
        () => codePushClientWrapper.setPatchRollout(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          patchId: any(named: 'patchId'),
          patchNumber: any(named: 'patchNumber'),
          rolloutPercentage: any(named: 'rolloutPercentage'),
        ),
      );
    }

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
      when(() => argResults['release-version']).thenReturn(releaseVersion);
      when(
        () => argResults['patch-number'],
      ).thenReturn(patchNumber.toString());
      when(() => argResults['percentage']).thenReturn('50');

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
      stubPatches([patch]);
      when(
        () => codePushClientWrapper.setPatchRollout(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          patchId: any(named: 'patchId'),
          patchNumber: any(named: 'patchNumber'),
          rolloutPercentage: any(named: 'rolloutPercentage'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(RolloutCommand.new)
        ..testArgResults = argResults;
    });

    test('is named rollout and takes the patch and a percentage', () {
      expect(command.name, equals('rollout'));
      final parsed = command.argParser.parse([
        '--release-version=1.0.0+1',
        '--patch-number=2',
        '--percentage=50',
      ]);
      expect(parsed['percentage'], equals('50'));
      expect(
        command.argParser.parse([
          '--release-version=1.0.0+1',
          '--patch-number=2',
          '--rollout=50',
        ])['percentage'],
        equals('50'),
        reason: '--rollout, as on patch and promote, works here too',
      );
      expect(command.argParser.options['percentage']!.mandatory, isTrue);
      expect(
        command.argParser.options.keys,
        containsAll(['app-id', 'flavor']),
      );
    });

    test('description says rollouts only go up and which devices count', () {
      expect(command.description, contains('it cannot lower it'));
      expect(command.description, contains(rolloutOlderDevicesNote));
      expect(command.description, contains('shorebird patches rollout '));
    });

    group('when --percentage is invalid', () {
      setUp(() {
        when(() => argResults['percentage']).thenReturn('0');
      });

      test('exits with usage error and does not fetch', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            '--percentage must be a percentage greater than 0 and at most '
            '100, with at most two decimal places, such as 10 or 0.5 '
            '(got "0").',
          ),
        ).called(1);
        verifyNever(
          () => codePushClientWrapper.getRelease(
            appId: any(named: 'appId'),
            releaseVersion: any(named: 'releaseVersion'),
          ),
        );
      });

      test('in --json mode, emits usage_error envelope', () async {
        final (:exitCode, :json) = await runJson();

        expect(exitCode, equals(ExitCode.usage.code));
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], 'usage_error');
      });
    });

    group('when --patch-number is not an integer', () {
      setUp(() {
        when(() => argResults['patch-number']).thenReturn('one');
      });

      test('exits with usage error', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verifyNoRolloutRequest();
      });
    });

    group('when validation fails', () {
      setUp(() {
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
            checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          ),
        ).thenThrow(ShorebirdNotInitializedException());
      });

      test('exits without asking the server', () async {
        final result = await runWithOverrides(command.run);

        expect(result, isNot(ExitCode.success.code));
        verifyNoRolloutRequest();
      });
    });

    group('when no matching patch is found', () {
      setUp(() => stubPatches([]));

      test('exits with usage error', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verifyNoRolloutRequest();
      });
    });

    group('when fetching patches fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getReleasePatches(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
          ),
        ).thenThrow(ProcessExit(ExitCode.software.code));
      });

      test('in --json mode, emits fetch_failed envelope', () async {
        final (:exitCode, :json) = await runJson();

        expect(exitCode, equals(ExitCode.software.code));
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], 'fetch_failed');
      });
    });

    group('when the patch is on no track', () {
      setUp(() {
        stubPatches([
          const ReleasePatch(
            id: 42,
            number: patchNumber,
            isRolledBack: false,
            artifacts: [],
          ),
        ]);
      });

      test('says how to put it on a track at that percentage', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            'Patch $patchNumber on release $releaseVersion is on no track, '
            'so it has no rollout to raise.',
          ),
        ).called(1);
        verify(
          () => logger.info(
            'Put it on a track at a percentage with: '
            'shorebird patches promote --release-version $releaseVersion '
            '--patch-number $patchNumber --rollout 50',
          ),
        ).called(1);
        verifyNoRolloutRequest();
      });

      test('passes --app-id and --flavor through to the hint', () async {
        when(() => argResults['app-id']).thenReturn('other-app');
        when(() => argResults['flavor']).thenReturn('dev');

        await runWithOverrides(command.run);

        verify(
          () => logger.info(
            'Put it on a track at a percentage with: '
            'shorebird patches promote --release-version $releaseVersion '
            '--patch-number $patchNumber --app-id other-app --flavor dev '
            '--rollout 50',
          ),
        ).called(1);
      });
    });

    group('when the server rejects the percentage', () {
      const error = CodePushConflictException(
        message: 'Rollouts only go up.',
        details: 'Patch 1 is at 60% of stable.',
        response: ErrorResponse(
          code: 'rollout_percentage_lower',
          message: 'Rollouts only go up.',
          details: 'Patch 1 is at 60% of stable.',
        ),
      );

      setUp(() {
        when(
          () => codePushClientWrapper.setPatchRollout(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            patchId: any(named: 'patchId'),
            patchNumber: any(named: 'patchNumber'),
            rolloutPercentage: any(named: 'rolloutPercentage'),
          ),
        ).thenThrow(ApiErrorExit(error, ExitCode.software.code));
      });

      test('lets the error through for the runner to report', () async {
        await expectLater(
          runWithOverrides(command.run),
          throwsA(isA<ApiErrorExit>()),
        );
      });

      test('in --json mode, emits the server message and code', () async {
        final (:exitCode, :json) = await runJson();

        expect(exitCode, equals(ExitCode.software.code));
        final jsonError = json['error'] as Map<String, dynamic>;
        expect(jsonError['code'], 'software_error');
        expect(
          jsonError['message'],
          'Failed to set the rollout of patch $patchNumber of release '
          '"$releaseVersion". Rollouts only go up.',
        );
        expect(jsonError['api_code'], 'rollout_percentage_lower');
        expect(jsonError['details'], 'Patch 1 is at 60% of stable.');
      });
    });

    group('when the rollout is raised', () {
      test('asks the server for the new percentage', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(
          () => codePushClientWrapper.setPatchRollout(
            appId: appId,
            releaseId: release.id,
            patchId: patch.id,
            patchNumber: patchNumber,
            rolloutPercentage: 50,
          ),
        ).called(1);
      });

      test('logs success, which devices count, and the patch', () async {
        await runWithOverrides(command.run);

        verifyInOrder([
          () => logger.success(
            'Patch $patchNumber on release $releaseVersion is now rolling '
            'out to 50% of devices on stable.',
          ),
          () => logger.info(rolloutOlderDevicesNote),
          () => logger.info('Track:       stable (50%)'),
        ]);
      });

      test('says so when the patch is already at that percentage', () async {
        when(() => argResults['percentage']).thenReturn('10');

        await runWithOverrides(command.run);

        verify(
          () => logger.success(
            'Patch $patchNumber on release $releaseVersion is already '
            'rolling out to 10% of devices on stable.',
          ),
        ).called(1);
        final (:exitCode, :json) = await runJson();
        expect(exitCode, equals(ExitCode.success.code));
        expect((json['data'] as Map<String, dynamic>)['changed'], isFalse);
      });

      test('says nothing about older devices at 100', () async {
        when(() => argResults['percentage']).thenReturn('100');

        await runWithOverrides(command.run);

        verifyNever(() => logger.info(rolloutOlderDevicesNote));
        verify(() => logger.info('Track:       stable')).called(1);
      });

      test('in --json mode, emits a success envelope', () async {
        final (:exitCode, :json) = await runJson();

        expect(exitCode, equals(ExitCode.success.code));
        expect(json['status'], 'success');
        final data = json['data'] as Map<String, dynamic>;
        expect(data['app_id'], appId);
        expect(data['release_version'], releaseVersion);
        expect(data['patch_number'], patchNumber);
        expect(data['action'], 'rollout');
        expect(data['changed'], isTrue);
        expect(data['rollout_percentage'], 50);
        expect(
          data['patch'],
          equals(
            const ReleasePatch(
              id: 42,
              number: patchNumber,
              channel: 'stable',
              isRolledBack: false,
              artifacts: [],
              rolloutPercentage: 50,
            ).toJson(),
          ),
        );
      });
    });

    group('when patches for several platforms share the number', () {
      const androidPatch = ReleasePatch(
        id: 10,
        number: patchNumber,
        channel: 'stable',
        isRolledBack: false,
        artifacts: [],
        rolloutPercentage: 10,
        platform: ReleasePlatform.android,
      );
      const iosPatch = ReleasePatch(
        id: 11,
        number: patchNumber,
        channel: 'stable',
        isRolledBack: false,
        artifacts: [],
        rolloutPercentage: 20,
        platform: ReleasePlatform.ios,
      );

      const iosOffTrack = ReleasePatch(
        id: 11,
        number: patchNumber,
        isRolledBack: false,
        artifacts: [],
        platform: ReleasePlatform.ios,
      );

      void verifyRolloutRequest(int patchId) {
        verify(
          () => codePushClientWrapper.setPatchRollout(
            appId: appId,
            releaseId: release.id,
            patchId: patchId,
            patchNumber: patchNumber,
            rolloutPercentage: 50,
          ),
        ).called(1);
      }

      void stubRolloutFailure(int patchId) {
        when(
          () => codePushClientWrapper.setPatchRollout(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            patchId: patchId,
            patchNumber: any(named: 'patchNumber'),
            rolloutPercentage: any(named: 'rolloutPercentage'),
          ),
        ).thenThrow(
          ApiErrorExit(
            const CodePushConflictException(
              message: 'stable is protected.',
              response: ErrorResponse(
                code: 'patch_rollout_protected_channel',
                message: 'stable is protected.',
              ),
            ),
            ExitCode.software.code,
          ),
        );
      }

      setUp(() {
        stubPatches([androidPatch, iosPatch]);
        when(() => argResults['platforms']).thenReturn(null);
        when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
        when(() => logger.confirm(any())).thenReturn(true);
      });

      test('takes --platforms', () {
        expect(
          command.argParser.parse([
            '--release-version=1.0.0+1',
            '--patch-number=2',
            '--percentage=50',
            '--platforms=android,ios',
          ])['platforms'],
          equals(['android', 'ios']),
        );
      });

      test('without --platforms, asks, then raises every platform', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(() => logger.confirm('Roll out all of them to 50%?')).called(1);
        verifyRolloutRequest(androidPatch.id);
        verifyRolloutRequest(iosPatch.id);
        verifyInOrder([
          () => logger.success(
            'Patch $patchNumber on release $releaseVersion is now rolling '
            'out to 50% of devices on stable (Android, iOS).',
          ),
          () => logger.info('Android:'),
          () => logger.info('  Track:       stable (50%)'),
          () => logger.info('iOS:'),
          () => logger.info('  Track:       stable (50%)'),
        ]);
      });

      test('when the prompt is declined, raises nothing', () async {
        when(() => logger.confirm(any())).thenReturn(false);

        await expectLater(
          runWithOverrides(command.run),
          throwsA(isA<PromptDeclinedExit>()),
        );
        verifyNoRolloutRequest();
      });

      test('with --platforms, raises only those without asking', () async {
        when(() => argResults['platforms']).thenReturn(['ios']);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verifyNever(() => logger.confirm(any()));
        verifyRolloutRequest(iosPatch.id);
        verifyNever(
          () => codePushClientWrapper.setPatchRollout(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            patchId: androidPatch.id,
            patchNumber: any(named: 'patchNumber'),
            rolloutPercentage: any(named: 'rolloutPercentage'),
          ),
        );
        verify(
          () => logger.success(
            'Patch $patchNumber on release $releaseVersion is now rolling '
            'out to 50% of devices on stable (iOS).',
          ),
        ).called(1);
      });

      test('refuses --platforms naming a platform with no patch', () async {
        when(() => argResults['platforms']).thenReturn(['macos']);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            'Patch $patchNumber on release $releaseVersion has no macOS patch.',
          ),
        ).called(1);
        verifyNoRolloutRequest();
      });

      test('without --platforms, refuses tracks that differ', () async {
        stubPatches([androidPatch, iosPatch.copyWith(channel: 'beta')]);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            "Patch $patchNumber's platforms are on different tracks, so pass "
            '--platforms to choose which to roll out further.',
          ),
        ).called(1);
        verify(
          () => logger.info(
            'To choose which to change, run:\n'
            '  shorebird rollout --release-version=$releaseVersion '
            '--patch-number=$patchNumber --percentage=50 '
            '--platforms=android',
          ),
        ).called(1);
        verifyNever(() => logger.confirm(any()));
        verifyNoRolloutRequest();
      });

      test('refuses a platform on no track before asking', () async {
        stubPatches([androidPatch, iosOffTrack]);
        when(() => argResults['platforms']).thenReturn(['android', 'ios']);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            "Patch $patchNumber's iOS patch on release $releaseVersion is on "
            'no track, so it has no rollout to raise.',
          ),
        ).called(1);
        verify(
          () => logger.info(
            'Put it on a track at a percentage with: '
            'shorebird patches promote --release-version $releaseVersion '
            '--patch-number $patchNumber --platforms ios --rollout 50',
          ),
        ).called(1);
        verifyNoRolloutRequest();
      });

      test('says when every platform is on no track', () async {
        stubPatches([
          const ReleasePatch(
            id: 10,
            number: patchNumber,
            isRolledBack: false,
            artifacts: [],
            platform: ReleasePlatform.android,
          ),
          iosOffTrack,
        ]);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            "Patch $patchNumber's Android and iOS patches on release "
            '$releaseVersion are on no track, so they have no rollout to '
            'raise.',
          ),
        ).called(1);
        verifyNever(() => logger.confirm(any()));
        verifyNoRolloutRequest();
      });

      test(
        'refuses before any request when one is above the percentage',
        () async {
          stubPatches([androidPatch, iosPatch.copyWith(rolloutPercentage: 80)]);

          final result = await runWithOverrides(command.run);

          expect(result, equals(ExitCode.usage.code));
          verify(
            () => logger.err(
              "Patch $patchNumber's iOS patch on release $releaseVersion is "
              'already rolling out to 80% of devices on stable, and a rollout '
              'can only be raised.',
            ),
          ).called(1);
          verify(
            () => logger.info(
              'To raise the others, pass --platforms without ios.',
            ),
          ).called(1);
          verifyNoRolloutRequest();
        },
      );

      test('says which platforms were raised when a later one fails', () async {
        stubRolloutFailure(iosPatch.id);

        await expectLater(
          runWithOverrides(command.run),
          throwsA(isA<ApiErrorExit>()),
        );
        verifyRolloutRequest(androidPatch.id);
        verify(
          () => logger.warn(
            'The rollout of patch $patchNumber was raised to 50% for Android, '
            'but not for iOS or any platform after it.',
          ),
        ).called(1);
      });

      test('says nothing was raised when the first one fails', () async {
        stubRolloutFailure(androidPatch.id);

        await expectLater(
          runWithOverrides(command.run),
          throwsA(isA<ApiErrorExit>()),
        );
        verifyNever(() => logger.warn(any()));
        verifyNever(
          () => codePushClientWrapper.setPatchRollout(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            patchId: iosPatch.id,
            patchNumber: any(named: 'patchNumber'),
            rolloutPercentage: any(named: 'rolloutPercentage'),
          ),
        );
      });

      group('in --json mode', () {
        test('emits every raised patch', () async {
          final (:exitCode, :json) = await runJson();

          expect(exitCode, equals(ExitCode.success.code));
          final data = json['data'] as Map<String, dynamic>;
          expect(data['changed'], isTrue);
          expect(
            data['patches'],
            equals([
              androidPatch.copyWith(rolloutPercentage: 50).toJson(),
              iosPatch.copyWith(rolloutPercentage: 50).toJson(),
            ]),
          );
          expect(
            data['patch'],
            equals(androidPatch.copyWith(rolloutPercentage: 50).toJson()),
          );
        });

        test(
          'says which platforms were raised when a later one fails',
          () async {
            stubRolloutFailure(iosPatch.id);

            final (:exitCode, :json) = await runJson();

            expect(exitCode, equals(ExitCode.software.code));
            final error = json['error'] as Map<String, dynamic>;
            expect(
              error['message'],
              'Failed to set the rollout of patch $patchNumber (iOS) of '
              'release "$releaseVersion" after raising Android to 50%. '
              'stable is protected.',
            );
            expect(error['api_code'], 'patch_rollout_protected_channel');
          },
        );
      });
    });
  });
}

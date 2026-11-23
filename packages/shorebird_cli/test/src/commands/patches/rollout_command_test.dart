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
import 'package:shorebird_cli/src/rollout_schedule.dart';
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
          rolloutSchedule: any(named: 'rolloutSchedule'),
          platforms: any(named: 'platforms'),
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
          rolloutSchedule: any(named: 'rolloutSchedule'),
          platforms: any(named: 'platforms'),
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
      expect(
        command.argParser.options['percentage']!.mandatory,
        isFalse,
        reason: '--$rolloutStepsArgName stands in for it',
      );
      expect(
        command.argParser.options.keys,
        containsAll([
          'app-id',
          'flavor',
          rolloutStepsArgName,
          pauseWeekendsArgName,
          timezoneArgName,
        ]),
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
            rolloutSchedule: any(named: 'rolloutSchedule'),
            platforms: any(named: 'platforms'),
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

    group('when neither --percentage nor --rollout-steps is given', () {
      setUp(() {
        when(() => argResults['percentage']).thenReturn(null);
      });

      test('exits with usage error and says what to pass', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            'Option --percentage is mandatory unless '
            '--$rolloutStepsArgName is given.',
          ),
        ).called(1);
        verify(
          () => logger.info(
            'Raise the rollout to a percentage with --percentage=50, or put '
            'it on a schedule with '
            '--$rolloutStepsArgName=$rolloutStepsExample.',
          ),
        ).called(1);
        verifyNoRolloutRequest();
      });
    });

    group('when --percentage and --rollout-steps are both given', () {
      setUp(() {
        when(
          () => argResults[rolloutStepsArgName],
        ).thenReturn(rolloutStepsExample);
      });

      test('exits with usage error', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            '--percentage and --$rolloutStepsArgName are mutually exclusive: '
            'a rollout is either a fixed percentage or a schedule.',
          ),
        ).called(1);
        verifyNoRolloutRequest();
      });
    });

    group('when --rollout-steps does not end at 100', () {
      setUp(() {
        when(() => argResults['percentage']).thenReturn(null);
        when(() => argResults[rolloutStepsArgName]).thenReturn('10:12h,50');
      });

      test('exits with usage error and does not fetch', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            '--$rolloutStepsArgName must end at 100, which is where the '
            'rollout stops (got "50").',
          ),
        ).called(1);
        verifyNever(
          () => codePushClientWrapper.getRelease(
            appId: any(named: 'appId'),
            releaseVersion: any(named: 'releaseVersion'),
          ),
        );
      });
    });

    group('when --pause-weekends is given without --rollout-steps', () {
      setUp(() {
        when(() => argResults[pauseWeekendsArgName]).thenReturn(true);
      });

      test('exits with usage error', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            '--$pauseWeekendsArgName only applies to a timed rollout '
            'schedule, which --$rolloutStepsArgName sets (e.g. '
            '--$rolloutStepsArgName=$rolloutStepsExample).',
          ),
        ).called(1);
        verifyNoRolloutRequest();
      });
    });

    group('when --rollout-steps is given', () {
      const schedule = RolloutSchedule(
        steps: [
          RolloutStep(percentage: 10, durationMinutes: 720),
          RolloutStep(percentage: 50, durationMinutes: 1440),
          RolloutStep(percentage: 100),
        ],
        pauseWeekends: true,
        timezone: 'America/New_York',
      );

      setUp(() {
        when(() => argResults['percentage']).thenReturn(null);
        when(
          () => argResults[rolloutStepsArgName],
        ).thenReturn('10:12h,50:1d,100');
        when(() => argResults[pauseWeekendsArgName]).thenReturn(true);
        when(
          () => argResults[timezoneArgName],
        ).thenReturn('America/New_York');
      });

      test('asks the server for the schedule', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(
          () => codePushClientWrapper.setPatchRollout(
            appId: appId,
            releaseId: release.id,
            patchId: patch.id,
            patchNumber: patchNumber,
            rolloutSchedule: schedule,
          ),
        ).called(1);
      });

      test('logs the schedule, which devices count, and the patch', () async {
        await runWithOverrides(command.run);

        verifyInOrder([
          () => logger.success(
            'Patch $patchNumber on release $releaseVersion is now rolling '
            'out on stable on a schedule: 10% for 12h, then 50% for 1d, then '
            '100%, holding over weekends in America/New_York.',
          ),
          () => logger.info(rolloutOlderDevicesNote),
          () => logger.info('Track:       stable (10%)'),
        ]);
      });

      test('in --json mode, emits the schedule', () async {
        final (:exitCode, :json) = await runJson();

        expect(exitCode, equals(ExitCode.success.code));
        final data = json['data'] as Map<String, dynamic>;
        expect(data['changed'], isTrue);
        expect(data['rollout_percentage'], 10);
        expect(
          data['rollout_steps'],
          equals([
            {'percentage': 10, 'duration_minutes': 720},
            {'percentage': 50, 'duration_minutes': 1440},
            {'percentage': 100},
          ]),
        );
        expect(data['rollout_pause_weekends'], isTrue);
        expect(data['rollout_timezone'], 'America/New_York');
      });

      test('reports a change at the first step the patch is at', () async {
        when(() => argResults[rolloutStepsArgName]).thenReturn('10:12h,100');
        when(() => argResults[pauseWeekendsArgName]).thenReturn(false);
        when(() => argResults[timezoneArgName]).thenReturn(null);

        final (:exitCode, :json) = await runJson();

        expect(exitCode, equals(ExitCode.success.code));
        expect((json['data'] as Map<String, dynamic>)['changed'], isTrue);
      });

      test('rejects a timezone that is not a zone name', () async {
        when(() => argResults[timezoneArgName]).thenReturn('New York');

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            '--$timezoneArgName must be an IANA time zone name, such as '
            'America/New_York (got "New York").',
          ),
        ).called(1);
        verifyNoRolloutRequest();
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

        test('says how to put it on a track on that schedule', () async {
          final result = await runWithOverrides(command.run);

          expect(result, equals(ExitCode.usage.code));
          verify(
            () => logger.info(
              'Put it on a track on that schedule with: '
              'shorebird patches promote --release-version $releaseVersion '
              '--patch-number $patchNumber '
              '--$rolloutStepsArgName 10:12h,50:1d,100 '
              '--$pauseWeekendsArgName '
              '--$timezoneArgName America/New_York',
            ),
          ).called(1);
          verifyNoRolloutRequest();
        });
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

    group('when the patch the server reports is on a schedule', () {
      setUp(() {
        stubPatches([
          ReleasePatch(
            id: patch.id,
            number: patch.number,
            channel: patch.channel,
            isRolledBack: patch.isRolledBack,
            artifacts: patch.artifacts,
            rolloutPercentage: patch.rolloutPercentage,
            rolloutSteps: const [
              RolloutStep(percentage: 10, durationMinutes: 720),
              RolloutStep(percentage: 100),
            ],
            rolloutNextStepAt: DateTime.utc(2026, 11, 11, 12),
            rolloutPauseWeekends: true,
            rolloutTimezone: 'America/New_York',
          ),
        ]);
      });

      test('in --json mode, a fixed rollout reports no schedule', () async {
        when(() => argResults['percentage']).thenReturn('100');

        final (:exitCode, :json) = await runJson();

        expect(exitCode, equals(ExitCode.success.code));
        final emitted =
            (json['data'] as Map<String, dynamic>)['patch']
                as Map<String, dynamic>;
        expect(emitted['rollout_percentage'], 100);
        expect(
          emitted.keys,
          isNot(
            anyElement(
              isIn([
                'rollout_steps',
                'rollout_next_step_at',
                'rollout_pause_weekends',
                'rollout_timezone',
              ]),
            ),
          ),
        );
      });

      test('in --json mode, a new schedule replaces the old one', () async {
        when(() => argResults['percentage']).thenReturn(null);
        when(() => argResults[rolloutStepsArgName]).thenReturn('1:4h,100');
        when(() => argResults[pauseWeekendsArgName]).thenReturn(false);
        when(() => argResults[timezoneArgName]).thenReturn(null);

        final (:exitCode, :json) = await runJson();

        expect(exitCode, equals(ExitCode.success.code));
        final emitted =
            (json['data'] as Map<String, dynamic>)['patch']
                as Map<String, dynamic>;
        expect(
          emitted['rollout_steps'],
          equals([
            {'percentage': 1, 'duration_minutes': 240},
            {'percentage': 100},
          ]),
        );
        expect(emitted['rollout_pause_weekends'], isFalse);
        expect(emitted.containsKey('rollout_timezone'), isFalse);
        expect(
          emitted.containsKey('rollout_next_step_at'),
          isFalse,
          reason: 'only the server knows when the next step applies',
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

      void verifyRolloutRequest({List<ReleasePlatform>? platforms}) => verify(
        () => codePushClientWrapper.setPatchRollout(
          appId: appId,
          releaseId: release.id,
          patchId: any(named: 'patchId'),
          patchNumber: patchNumber,
          rolloutPercentage: 50,
          platforms: platforms,
        ),
      ).called(1);

      setUp(() {
        stubPatches([androidPatch, iosPatch]);
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

      test('without --platforms asks, then raises every platform', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(() => logger.confirm('Roll out all of them to 50%?')).called(1);
        // One request without platforms, which the server applies to every
        // platform's patch under the number.
        verifyRolloutRequest();
        verify(
          () => logger.success(
            'Patch $patchNumber on release $releaseVersion is now rolling out '
            'to 50% of devices on stable (Android, iOS).',
          ),
        ).called(1);
        verify(() => logger.info('Android:')).called(1);
        verify(() => logger.info('iOS:')).called(1);
      });

      test('raises nothing when the prompt is declined', () async {
        when(() => logger.confirm(any())).thenReturn(false);

        await expectLater(
          runWithOverrides(command.run),
          throwsA(isA<PromptDeclinedExit>()),
        );
        verifyNoRolloutRequest();
      });

      test('with --platforms raises only those, without asking', () async {
        when(() => argResults['platforms']).thenReturn(['ios']);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verifyNever(() => logger.confirm(any()));
        verifyRolloutRequest(platforms: [ReleasePlatform.ios]);
        verify(
          () => logger.success(
            'Patch $patchNumber on release $releaseVersion is now rolling out '
            'to 50% of devices on stable (iOS).',
          ),
        ).called(1);
      });

      test('refuses a platform the number has no patch for', () async {
        when(() => argResults['platforms']).thenReturn(['macos']);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verifyNoRolloutRequest();
      });

      test('refuses, before asking, tracks that differ', () async {
        stubPatches([androidPatch, iosPatch.copyWith(channel: 'beta')]);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            "Patch $patchNumber's platforms are on different tracks, so pass "
            '--platforms to choose which to roll out.',
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

      test('refuses a platform already rolling out further', () async {
        stubPatches([androidPatch.copyWith(rolloutPercentage: 60), iosPatch]);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            'Patch $patchNumber on release $releaseVersion is already '
            'rolling out further than 50% on stable for Android, and a '
            'rollout can only be raised.',
          ),
        ).called(1);
        verify(
          () => logger.info(
            'To raise only the others, run: shorebird rollout '
            '--release-version=$releaseVersion --patch-number=$patchNumber '
            '--percentage=50 --platforms=ios',
          ),
        ).called(1);
        verifyNever(() => logger.confirm(any()));
        verifyNoRolloutRequest();
      });

      test('gives no hint when every platform is further along', () async {
        stubPatches([
          androidPatch.copyWith(rolloutPercentage: 60),
          iosPatch.copyWith(rolloutPercentage: 70),
        ]);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            'Patch $patchNumber on release $releaseVersion is already '
            'rolling out further than 50% on stable for Android, iOS, and a '
            'rollout can only be raised.',
          ),
        ).called(1);
        verifyNever(
          () => logger.info(any(that: startsWith('To raise only the others'))),
        );
        verifyNoRolloutRequest();
      });

      test(
        'leaves a single chosen platform further along to the server',
        () async {
          stubPatches([androidPatch, iosPatch.copyWith(rolloutPercentage: 60)]);
          when(() => argResults['platforms']).thenReturn(['ios']);

          final result = await runWithOverrides(command.run);

          expect(result, equals(ExitCode.success.code));
          verifyNever(
            () => logger.err(any(that: contains('already rolling out'))),
          );
          verifyRolloutRequest(platforms: [ReleasePlatform.ios]);
        },
      );

      test(
        'names the platforms in the promote hint when on no track',
        () async {
          stubPatches([
            for (final p in [androidPatch, iosPatch])
              ReleasePatch(
                id: p.id,
                number: p.number,
                isRolledBack: false,
                artifacts: const [],
                platform: p.platform,
              ),
          ]);
          when(() => argResults['platforms']).thenReturn(['ios']);

          final result = await runWithOverrides(command.run);

          expect(result, equals(ExitCode.usage.code));
          verify(
            () => logger.err(
              'Patch $patchNumber on release $releaseVersion is on no track '
              '(iOS), so it has no rollout to raise.',
            ),
          ).called(1);
          verify(
            () => logger.info(
              'Put it on a track at a percentage with: '
              'shorebird patches promote --release-version $releaseVersion '
              '--patch-number $patchNumber --rollout 50 --platforms ios',
            ),
          ).called(1);
        },
      );

      test('in --json mode, lists every patch it raised', () async {
        final (:exitCode, :json) = await runJson();

        expect(exitCode, equals(ExitCode.success.code));
        final data = json['data'] as Map<String, dynamic>;
        final emitted = (data['patches'] as List).cast<Map<String, dynamic>>();
        expect(emitted.map((p) => p['id']), equals([10, 11]));
        expect(
          emitted.map((p) => p['rollout_percentage']),
          equals([50, 50]),
        );
        expect((data['patch'] as Map<String, dynamic>)['id'], equals(10));
      });

      test('reports a failed request once, for every platform', () async {
        when(
          () => codePushClientWrapper.setPatchRollout(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            patchId: any(named: 'patchId'),
            patchNumber: any(named: 'patchNumber'),
            rolloutPercentage: any(named: 'rolloutPercentage'),
            rolloutSchedule: any(named: 'rolloutSchedule'),
            platforms: any(named: 'platforms'),
          ),
        ).thenThrow(
          ApiErrorExit(
            const CodePushConflictException(
              message: 'Rollouts only go up.',
              response: ErrorResponse(
                code: 'rollout_percentage_lower',
                message: 'Rollouts only go up.',
              ),
            ),
            ExitCode.software.code,
          ),
        );

        final (:exitCode, :json) = await runJson();

        expect(exitCode, equals(ExitCode.software.code));
        expect(
          (json['error'] as Map<String, dynamic>)['message'],
          'Failed to set the rollout of patch $patchNumber of release '
          '"$releaseVersion". Rollouts only go up.',
        );
      });

      group('when the server says the platforms differ', () {
        setUp(() {
          when(
            () => codePushClientWrapper.setPatchRollout(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
              patchId: any(named: 'patchId'),
              patchNumber: any(named: 'patchNumber'),
              rolloutPercentage: any(named: 'rolloutPercentage'),
              rolloutSchedule: any(named: 'rolloutSchedule'),
              platforms: any(named: 'platforms'),
            ),
          ).thenThrow(
            ApiErrorExit(
              const CodePushConflictException(
                message: 'Upgrade the Shorebird CLI or use the console.',
                response: ErrorResponse(
                  code: 'patch_platforms_differ',
                  message: 'Upgrade the Shorebird CLI or use the console.',
                ),
              ),
              ExitCode.software.code,
            ),
          );
        });

        test('prints each platform and the --platforms command', () async {
          final result = await runWithOverrides(command.run);

          expect(result, equals(ExitCode.software.code));
          verify(
            () => logger.info(
              'To choose which to change, run:\n'
              '  shorebird rollout --release-version=$releaseVersion '
              '--patch-number=$patchNumber --percentage=50 '
              '--platforms=android,ios',
            ),
          ).called(1);
        });

        test("in --json mode, does not pass on the server's message", () async {
          final (:exitCode, :json) = await runJson();

          expect(exitCode, equals(ExitCode.software.code));
          final error = json['error'] as Map<String, dynamic>;
          expect(error['api_code'], equals('patch_platforms_differ'));
          expect(error['message'], isNot(contains('Upgrade')));
          expect(error['hint'], contains('--platforms=android,ios'));
        });
      });
    });
  });
}

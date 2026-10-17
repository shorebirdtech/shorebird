import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patches/patches.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(PromoteCommand, () {
    const appId = 'app-id';
    const releaseVersion = '1.0.0';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final release = Release(
      id: 0,
      appId: appId,
      version: releaseVersion,
      flutterRevision: 'flutter-revision',
      flutterVersion: 'flutter-version',
      displayName: releaseVersion,
      platformStatuses: const {ReleasePlatform.android: ReleaseStatus.active},
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
    final stableChannel = Channel(
      id: 0,
      appId: appId,
      name: DeploymentTrack.stable.channel,
    );
    const betaChannel = Channel(id: 1, appId: appId, name: 'beta');

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
          isJsonModeRef.overrideWith(() => false),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    void parse(List<String> args) {
      command.testArgResults = command.argParser.parse([
        '--release-version',
        releaseVersion,
        '--patch-number',
        '1',
        ...args,
      ]);
    }

    setUpAll(() {
      registerFallbackValue(FakeChannel());
    });

    setUp(() {
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();

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
          name: DeploymentTrack.stable.channel,
        ),
      ).thenAnswer((_) async => stableChannel);
      when(
        () => codePushClientWrapper.maybeGetChannel(
          appId: any(named: 'appId'),
          name: betaChannel.name,
        ),
      ).thenAnswer((_) async => betaChannel);
      when(
        () => codePushClientWrapper.promotePatch(
          appId: any(named: 'appId'),
          patchId: any(named: 'patchId'),
          channel: any(named: 'channel'),
        ),
      ).thenAnswer((_) async => {});

      command = runWithOverrides(PromoteCommand.new);
    });

    test('is named promote and shown in help', () {
      expect(command.name, equals('promote'));
      expect(command.hidden, isFalse);
    });

    test('description points at set-track', () {
      expect(
        command.description,
        contains('shorebird patches set-track --track stable'),
      );
    });

    test('--track defaults to stable', () {
      parse([]);
      expect(command.results['track'], equals('stable'));
    });

    test('accepts --channel as an alias of --track', () {
      parse(['--channel', 'beta']);
      expect(command.results['track'], equals('beta'));
    });

    test('promotes the patch to stable by default', () async {
      parse([]);

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => codePushClientWrapper.promotePatch(
          appId: appId,
          patchId: patch.id,
          channel: stableChannel,
        ),
      ).called(1);
      verify(
        () => logger.success(
          'Patch 1 on release $releaseVersion is now in channel stable!',
        ),
      ).called(1);
    });

    test('promotes the patch to the track given by --channel', () async {
      parse(['--channel', 'beta']);

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => codePushClientWrapper.promotePatch(
          appId: appId,
          patchId: patch.id,
          channel: betaChannel,
        ),
      ).called(1);
    });

    test('succeeds without changes when already on stable', () async {
      when(
        () => codePushClientWrapper.getReleasePatches(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      ).thenAnswer(
        (_) async => [patch.copyWith(channel: DeploymentTrack.stable.channel)],
      );
      parse([]);

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verify(
        () => logger.info(
          'Patch 1 on release $releaseVersion is already in channel stable.',
        ),
      ).called(1);
      verifyNever(
        () => codePushClientWrapper.promotePatch(
          appId: any(named: 'appId'),
          patchId: any(named: 'patchId'),
          channel: any(named: 'channel'),
        ),
      );
    });

    test('--json emits the set-track success envelope', () async {
      parse([]);

      final (:exitCode, :json) = await captureJson(
        () => runScoped(
          command.run,
          values: {
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
            isJsonModeRef.overrideWith(() => true),
            loggerRef.overrideWith(() => logger),
            shorebirdEnvRef.overrideWith(() => shorebirdEnv),
            shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          },
        ),
      );

      expect(exitCode, equals(ExitCode.success.code));
      final data = json['data'] as Map<String, dynamic>;
      expect(data['track'], equals('stable'));
      expect(data['changed'], isTrue);
    });
  });
}

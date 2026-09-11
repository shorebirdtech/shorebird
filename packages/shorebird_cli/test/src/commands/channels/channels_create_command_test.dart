import 'dart:convert';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/channels/channels.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  group(ChannelsCreateCommand, () {
    const appId = 'app-id';
    const channelName = 'qa';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const stableChannel = Channel(id: 1, appId: appId, name: 'stable');
    const qaChannel = Channel(id: 7, appId: appId, name: channelName);

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late ChannelsCreateCommand command;

    R runWithOverrides<R>(
      R Function() body, {
      bool jsonMode = false,
    }) {
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

    void verifyNeverCreated() {
      verifyNever(
        () => codePushClientWrapper.createChannel(
          appId: any(named: 'appId'),
          name: any(named: 'name'),
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
      when(() => argResults['name']).thenReturn(channelName);

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async => {});
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);

      when(
        () => codePushClientWrapper.getChannels(appId: any(named: 'appId')),
      ).thenAnswer((_) async => [stableChannel]);
      when(
        () => codePushClientWrapper.createChannel(
          appId: any(named: 'appId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => qaChannel);

      command = runWithOverrides(ChannelsCreateCommand.new)
        ..testArgResults = argResults;
    });

    test('name and description are correct', () {
      expect(command.name, 'create');
      expect(
        command.description,
        startsWith('Creates a channel an app can publish to.'),
      );
    });

    test('creates the channel', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(
        () => codePushClientWrapper.createChannel(
          appId: appId,
          name: channelName,
        ),
      ).called(1);
      verify(() => logger.success('Created channel "$channelName".')).called(1);
    });

    group('when the name is invalid', () {
      test('rejects an empty name', () async {
        when(() => argResults['name']).thenReturn('');
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverCreated();
      });

      test('rejects a name that is too long', () async {
        when(() => argResults['name']).thenReturn(
          'a' * (CommonArguments.trackNameMaxLength + 1),
        );
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverCreated();
      });

      test('emits a usage_error envelope under --json', () async {
        when(() => argResults['name']).thenReturn('');
        final captured = <String>[];
        final result = await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        expect(result, equals(ExitCode.usage.code));
        verifyNeverCreated();
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(
          (decoded['error'] as Map<String, dynamic>)['code'],
          'usage_error',
        );
      });
    });

    group('when the channel already exists', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getChannels(appId: any(named: 'appId')),
        ).thenAnswer((_) async => [stableChannel, qaChannel]);
      });

      test('exits with usage and does not create', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverCreated();
      });

      test('emits a usage_error envelope under --json', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        expect(result, equals(ExitCode.usage.code));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(
          (decoded['error'] as Map<String, dynamic>)['code'],
          'usage_error',
        );
      });
    });

    group('when the fetch fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getChannels(appId: any(named: 'appId')),
        ).thenThrow(ProcessExit(ExitCode.software.code));
      });

      test('emits a JSON error envelope in --json mode', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        expect(result, equals(ExitCode.software.code));
        verifyNeverCreated();
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(
          (decoded['error'] as Map<String, dynamic>)['code'],
          'fetch_failed',
        );
      });
    });

    group('when the create fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.createChannel(
            appId: any(named: 'appId'),
            name: any(named: 'name'),
          ),
        ).thenThrow(ProcessExit(ExitCode.software.code));
      });

      test('rethrows in human-readable mode', () async {
        await expectLater(
          runWithOverrides(command.run),
          throwsA(isA<ProcessExit>()),
        );
      });

      test('emits a JSON error envelope in --json mode', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        expect(result, equals(ExitCode.software.code));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(
          (decoded['error'] as Map<String, dynamic>)['code'],
          'software_error',
        );
      });
    });

    group('--json', () {
      test('emits the created channel', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        expect(result, equals(ExitCode.success.code));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        final data = decoded['data'] as Map<String, dynamic>;
        expect(data['name'], channelName);
        expect(data['channel'], equals(qaChannel.toJson()));
      });
    });
  });
}

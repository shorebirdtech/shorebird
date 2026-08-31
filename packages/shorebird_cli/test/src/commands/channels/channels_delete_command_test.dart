import 'dart:convert';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/channels/channels.dart';
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
  group(ChannelsDeleteCommand, () {
    const appId = 'app-id';
    const channelName = 'qa';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const qaChannel = Channel(id: 7, appId: appId, name: channelName);
    const stableChannel = Channel(id: 1, appId: appId, name: 'stable');

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late ChannelsDeleteCommand command;

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

    void verifyNeverDeleted() {
      verifyNever(
        () => codePushClientWrapper.deleteChannel(
          appId: any(named: 'appId'),
          channelId: any(named: 'channelId'),
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
      when(() => argResults['confirm-name']).thenReturn(channelName);

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async => {});
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);

      when(
        () => codePushClientWrapper.getChannels(appId: any(named: 'appId')),
      ).thenAnswer((_) async => [stableChannel, qaChannel]);
      when(
        () => codePushClientWrapper.deleteChannel(
          appId: any(named: 'appId'),
          channelId: any(named: 'channelId'),
        ),
      ).thenAnswer((_) async => {});

      command = runWithOverrides(ChannelsDeleteCommand.new)
        ..testArgResults = argResults;
    });

    test('name and description are correct', () {
      expect(command.name, 'delete');
      expect(
        command.description,
        startsWith('Deletes a channel from an app.'),
      );
    });

    test('resolves the name to an id and deletes it', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(
        () => codePushClientWrapper.deleteChannel(
          appId: appId,
          channelId: qaChannel.id,
        ),
      ).called(1);
      verify(() => logger.success('Deleted channel "$channelName".')).called(1);
    });

    group('when the channel does not exist', () {
      setUp(() => when(() => argResults['name']).thenReturn('nope'));

      test('exits with usage and lists what is available', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverDeleted();
        verify(() => logger.info('Available channels: stable, qa')).called(1);
      });

      test('emits a usage_error envelope under --json', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        expect(result, equals(ExitCode.usage.code));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        final error = decoded['error'] as Map<String, dynamic>;
        expect(error['code'], 'usage_error');
        expect(error['hint'], 'Available channels: stable, qa');
      });
    });

    group('the --confirm-name gate', () {
      test('refuses when absent', () async {
        when(() => argResults['confirm-name']).thenReturn(null);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverDeleted();
      });

      test('refuses when it does not match', () async {
        when(() => argResults['confirm-name']).thenReturn('stable');
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverDeleted();
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
        verifyNeverDeleted();
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(
          (decoded['error'] as Map<String, dynamic>)['code'],
          'fetch_failed',
        );
      });
    });

    group('when the delete fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.deleteChannel(
            appId: any(named: 'appId'),
            channelId: any(named: 'channelId'),
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
      test('emits the resolved channel id', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        expect(result, equals(ExitCode.success.code));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        final data = decoded['data'] as Map<String, dynamic>;
        expect(data['name'], channelName);
        expect(data['channel_id'], qaChannel.id);
        expect(data['is_default_track'], isFalse);
        expect(data['deleted'], isTrue);
      });
    });

    group('when the channel backs a built-in track', () {
      setUp(() {
        when(() => argResults['name']).thenReturn('stable');
        when(() => argResults['confirm-name']).thenReturn('stable');
      });

      test('flags is_default_track', () async {
        final captured = <String>[];
        await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(
          (decoded['data'] as Map<String, dynamic>)['is_default_track'],
          isTrue,
        );
      });

      test('warns before the confirmation gate', () async {
        when(() => argResults['confirm-name']).thenReturn(null);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverDeleted();
        verify(
          () => logger.warn(any(that: contains('built-in tracks'))),
        ).called(1);
      });

      // The CLI documents permanence in help rather than enforcing it here.
      test('sends the delete rather than blocking locally', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => codePushClientWrapper.deleteChannel(
            appId: appId,
            channelId: stableChannel.id,
          ),
        ).called(1);
      });
    });
  });
}

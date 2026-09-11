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
  group(ChannelsListCommand, () {
    const appId = 'app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const stableChannel = Channel(id: 1, appId: appId, name: 'stable');
    const qaChannel = Channel(id: 7, appId: appId, name: 'qa');

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late ChannelsListCommand command;

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

      command = runWithOverrides(ChannelsListCommand.new)
        ..testArgResults = argResults;
    });

    test('name and description are correct', () {
      expect(command.name, 'list');
      expect(
        command.description,
        startsWith('Lists the channels an app can publish to.'),
      );
    });

    test('lists each channel', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('1  stable')).called(1);
      verify(() => logger.info('7  qa')).called(1);
    });

    group('when there are no channels', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getChannels(appId: any(named: 'appId')),
        ).thenAnswer((_) async => []);
      });

      test('says so', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info('No channels found for app $appId.'),
        ).called(1);
      });

      test('emits an empty list under --json', () async {
        final captured = <String>[];
        await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect((decoded['data'] as Map<String, dynamic>)['channels'], isEmpty);
      });
    });

    group('when the fetch fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getChannels(appId: any(named: 'appId')),
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
          'fetch_failed',
        );
      });
    });

    group('--json', () {
      test('emits the channels', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        expect(result, equals(ExitCode.success.code));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(
          (decoded['data'] as Map<String, dynamic>)['channels'],
          equals([stableChannel.toJson(), qaChannel.toJson()]),
        );
      });
    });
  });
}

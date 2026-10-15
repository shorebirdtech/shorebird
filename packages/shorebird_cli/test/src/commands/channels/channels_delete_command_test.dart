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
  useTempWorkingDirectory();
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
      when(() => argResults['yes']).thenReturn(true);
      when(() => argResults['confirm-name']).thenReturn(null);
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);

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
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.usage.code));
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], 'usage_error');
        expect(error['hint'], 'Available channels: stable, qa');
      });
    });

    group('confirmation', () {
      setUp(() => when(() => argResults['yes']).thenReturn(false));

      test('requires --yes when not interactive', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverDeleted();
        verify(
          () => logger.err('--yes required when not running interactively'),
        ).called(1);
        verify(
          () => logger.info(
            'Re-run with --yes to delete channel "$channelName" from app '
            '"$appId".',
          ),
        ).called(1);
      });

      test('emits a usage_error envelope under --json', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.usage.code));
        verifyNeverDeleted();
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], 'usage_error');
        expect(
          error['message'],
          '--yes required when not running interactively',
        );
      });

      group('when stdin is a terminal but stdout is not', () {
        setUp(
          () => when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true),
        );

        test('requires --yes without prompting', () async {
          final result = await captureStdout(
            () => runWithOverrides(command.run),
            captured: [],
            hasTerminal: false,
          );
          expect(result, equals(ExitCode.usage.code));
          verifyNeverDeleted();
          verify(
            () => logger.err('--yes required when not running interactively'),
          ).called(1);
          verifyNever(() => logger.prompt(any(), hint: any(named: 'hint')));
          verifyNever(() => logger.confirm(any(), hint: any(named: 'hint')));
        });
      });

      group('in a terminal', () {
        Future<int> runInTerminal() => captureStdout(
          () => runWithOverrides(command.run),
          captured: [],
          hasTerminal: true,
        );

        setUp(
          () => when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true),
        );

        test('deletes when confirmed', () async {
          when(
            () => logger.confirm(any(), hint: any(named: 'hint')),
          ).thenReturn(true);
          final result = await runInTerminal();
          expect(result, equals(ExitCode.success.code));
          verify(
            () => logger.confirm(
              'Delete channel "$channelName" from app "$appId"?',
              hint:
                  'Re-run with --yes to delete channel "$channelName" from '
                  'app "$appId".',
            ),
          ).called(1);
          verify(
            () => codePushClientWrapper.deleteChannel(
              appId: appId,
              channelId: qaChannel.id,
            ),
          ).called(1);
        });

        test('does nothing when declined', () async {
          when(
            () => logger.confirm(any(), hint: any(named: 'hint')),
          ).thenReturn(false);
          final result = await runInTerminal();
          expect(result, equals(ExitCode.success.code));
          verifyNeverDeleted();
          verify(() => logger.info('Nothing was deleted.')).called(1);
        });
      });

      group('with the deprecated --confirm-name', () {
        test('deletes when it matches', () async {
          when(() => argResults['confirm-name']).thenReturn(channelName);
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verify(
            () => logger.warn(any(that: contains('deprecated'))),
          ).called(1);
        });

        test('refuses when it does not match', () async {
          when(() => argResults['confirm-name']).thenReturn('stable');
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.usage.code));
          verifyNeverDeleted();
        });
      });
    });

    group('when the fetch fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getChannels(appId: any(named: 'appId')),
        ).thenThrow(ProcessExit(ExitCode.software.code));
      });

      test('emits a JSON error envelope in --json mode', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.software.code));
        verifyNeverDeleted();
        expect(
          (json['error'] as Map<String, dynamic>)['code'],
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

      test('emits a JSON error envelope in --json mode', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.software.code));
        expect(
          (json['error'] as Map<String, dynamic>)['code'],
          'software_error',
        );
      });
    });

    group('--json', () {
      test('emits the resolved channel id', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.success.code));
        final data = json['data'] as Map<String, dynamic>;
        expect(data['name'], channelName);
        expect(data['channel_id'], qaChannel.id);
        expect(data.containsKey('is_default_track'), isFalse);
        expect(data['deleted'], isTrue);
      });
    });

    group('when the channel backs a built-in track', () {
      void verifyNoServerCalls() {
        verifyNever(
          () => codePushClientWrapper.getChannels(appId: any(named: 'appId')),
        );
        verifyNeverDeleted();
      }

      for (final track in ['stable', 'beta', 'staging']) {
        group(track, () {
          setUp(() {
            when(() => argResults['name']).thenReturn(track);
          });

          test('refuses before any server call', () async {
            final result = await runWithOverrides(command.run);
            expect(result, equals(ExitCode.usage.code));
            verifyNoServerCalls();
            verify(
              () => logger.err(
                '"$track" is one of Shorebird\'s built-in tracks and cannot '
                'be deleted.',
              ),
            ).called(1);
            verify(
              () => logger.info(any(that: contains('unpublish every patch'))),
            ).called(1);
          });

          test('emits a usage_error envelope under --json', () async {
            final (:exitCode, :json) = await captureJson(
              () => runWithOverrides(command.run, jsonMode: true),
            );
            expect(exitCode, equals(ExitCode.usage.code));
            verifyNoServerCalls();
            final error = json['error'] as Map<String, dynamic>;
            expect(error['code'], 'usage_error');
            expect(
              error['message'],
              '"$track" is one of Shorebird\'s built-in tracks and cannot be '
              'deleted.',
            );
            expect(error['hint'], contains('unpublish every patch'));
          });
        });
      }
    });
  });
}

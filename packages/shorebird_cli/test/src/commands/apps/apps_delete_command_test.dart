import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/apps/apps.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
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
  group(AppsDeleteCommand, () {
    const appId = 'app-id';
    const displayName = 'Acme Mobile';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final app = AppMetadata(
      appId: appId,
      displayName: displayName,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final release = Release(
      id: 0,
      appId: appId,
      version: '1.0.0+1',
      flutterRevision: 'flutter-revision',
      flutterVersion: 'flutter-version',
      displayName: '1.0.0+1',
      platformStatuses: const {
        ReleasePlatform.android: ReleaseStatus.active,
        ReleasePlatform.ios: ReleaseStatus.active,
      },
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late AppsDeleteCommand command;

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
        () => codePushClientWrapper.deleteApp(appId: any(named: 'appId')),
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
      when(() => argResults['confirm-name']).thenReturn(displayName);
      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async => {});
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);

      when(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
      ).thenAnswer((_) async => app);
      when(
        () => codePushClientWrapper.getReleases(
          appId: any(named: 'appId'),
          sideloadableOnly: any(named: 'sideloadableOnly'),
        ),
      ).thenAnswer((_) async => [release]);
      when(
        () => codePushClientWrapper.deleteApp(appId: any(named: 'appId')),
      ).thenAnswer((_) async => {});

      command = runWithOverrides(AppsDeleteCommand.new)
        ..testArgResults = argResults;
    });

    test('name and description are correct', () {
      expect(command.name, 'delete');
      expect(command.description, startsWith('Permanently deletes an app.'));
    });

    test('has --confirm-name and no --yes', () {
      final option = command.argParser.options['confirm-name']!;
      expect(option.hide, isFalse);
      expect(option.help, contains("The app's display name"));
      expect(command.argParser.options.containsKey('yes'), isFalse);
    });

    test('deletes the app with a matching --confirm-name', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(() => codePushClientWrapper.deleteApp(appId: appId)).called(1);
      verify(
        () => logger.success('Deleted "$displayName" ($appId).'),
      ).called(1);
    });

    group('confirmation', () {
      setUp(() => when(() => argResults['confirm-name']).thenReturn(null));

      test('requires --confirm-name when not interactive', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverDeleted();
        verify(
          () => logger.err(
            '--confirm-name required when not running interactively',
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
          '--confirm-name required when not running interactively',
        );
        expect(error['hint'], contains('--confirm-name "$displayName"'));
      });

      group('when stdin is a terminal but stdout is not', () {
        setUp(
          () => when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true),
        );

        test('requires --confirm-name without prompting', () async {
          final result = await captureStdout(
            () => runWithOverrides(command.run),
            captured: [],
            hasTerminal: false,
          );
          expect(result, equals(ExitCode.usage.code));
          verifyNeverDeleted();
          verify(
            () => logger.err(
              '--confirm-name required when not running interactively',
            ),
          ).called(1);
          verifyNever(() => logger.info(any(that: contains('permanently'))));
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

        test('deletes when the typed name matches', () async {
          when(
            () => logger.prompt(any(), hint: any(named: 'hint')),
          ).thenReturn(displayName);
          final result = await runInTerminal();
          expect(result, equals(ExitCode.success.code));
          verify(
            () => logger.info(
              'This permanently deletes app "$displayName" ($appId), its 1 '
              'release and every patch. Devices running it stop getting '
              'patches.',
            ),
          ).called(1);
          verify(
            () => logger.prompt(
              'Type $displayName to confirm deletion:',
              hint: any(named: 'hint'),
            ),
          ).called(1);
          verify(() => codePushClientWrapper.deleteApp(appId: appId)).called(1);
        });

        test('exits 1 when the typed name does not match', () async {
          when(
            () => logger.prompt(any(), hint: any(named: 'hint')),
          ).thenReturn('Wrong Name');
          final result = await runInTerminal();
          expect(result, equals(declinedExitCode));
          verifyNeverDeleted();
          verify(
            () => logger.err(
              '"Wrong Name" does not match "$displayName". Nothing was '
              'deleted.',
            ),
          ).called(1);
        });
      });

      test('rejects a --confirm-name that does not match', () async {
        when(() => argResults['confirm-name']).thenReturn('Wrong Name');
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverDeleted();
        verify(
          () => logger.err(
            '--confirm-name "Wrong Name" does not match "$displayName".',
          ),
        ).called(1);
        verifyNever(() => logger.warn(any()));
      });
    });

    group('describes how many releases are deleted', () {
      Future<void> expectConsequence(int count, String phrase) async {
        when(
          () => codePushClientWrapper.getReleases(
            appId: any(named: 'appId'),
            sideloadableOnly: any(named: 'sideloadableOnly'),
          ),
        ).thenAnswer((_) async => List.filled(count, release));
        when(() => argResults['confirm-name']).thenReturn(null);
        when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);
        when(
          () => logger.prompt(any(), hint: any(named: 'hint')),
        ).thenReturn(displayName);
        await captureStdout(
          () => runWithOverrides(command.run),
          captured: [],
          hasTerminal: true,
        );
        verify(() => logger.info(any(that: contains(phrase)))).called(1);
      }

      test('with no releases', () async {
        await expectConsequence(0, '($appId), which has no releases, and');
      });

      test('with several releases', () async {
        await expectConsequence(3, '($appId), all 3 of its releases and');
      });
    });

    group('when the delete fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.deleteApp(appId: any(named: 'appId')),
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

    group('when the fetch fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
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

    group('--json', () {
      test('reports what was destroyed', () async {
        final (:exitCode, :json) = await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        );
        expect(exitCode, equals(ExitCode.success.code));
        final data = json['data'] as Map<String, dynamic>;
        expect(data['app_id'], appId);
        expect(data['display_name'], displayName);
        expect(data['release_count'], 1);
        expect(data['platforms'], equals(['android', 'ios']));
        expect(data['deleted'], isTrue);
      });

      test('handles an app with no releases', () async {
        when(
          () => codePushClientWrapper.getReleases(
            appId: any(named: 'appId'),
            sideloadableOnly: any(named: 'sideloadableOnly'),
          ),
        ).thenAnswer((_) async => []);
        final json = (await captureJson(
          () => runWithOverrides(command.run, jsonMode: true),
        )).json;
        final data = json['data'] as Map<String, dynamic>;
        expect(data['release_count'], 0);
        expect(data['platforms'], isEmpty);
      });
    });
  });
}

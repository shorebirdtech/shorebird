import 'dart:convert';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/apps/apps.dart';
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

    test('deletes the app when the name matches', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(() => codePushClientWrapper.deleteApp(appId: appId)).called(1);
      verify(
        () => logger.success('Deleted "$displayName" ($appId).'),
      ).called(1);
    });

    group('the --confirm-name gate', () {
      test('refuses when --confirm-name is absent', () async {
        when(() => argResults['confirm-name']).thenReturn(null);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverDeleted();
        verify(
          () => logger.info('Re-run with --confirm-name="$displayName".'),
        ).called(1);
      });

      test('refuses when --confirm-name does not match', () async {
        when(() => argResults['confirm-name']).thenReturn('Wrong Name');
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNeverDeleted();
      });

      test('emits a usage_error envelope under --json', () async {
        when(() => argResults['confirm-name']).thenReturn(null);
        final captured = <String>[];
        final result = await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        expect(result, equals(ExitCode.usage.code));
        verifyNeverDeleted();
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        final error = decoded['error'] as Map<String, dynamic>;
        expect(error['code'], 'usage_error');
        expect(error['hint'], contains(displayName));
      });
    });

    group('when the delete fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.deleteApp(appId: any(named: 'appId')),
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

    group('when the fetch fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
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

    group('--json', () {
      test('reports what was destroyed', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        expect(result, equals(ExitCode.success.code));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        final data = decoded['data'] as Map<String, dynamic>;
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
        final captured = <String>[];
        await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        final data = decoded['data'] as Map<String, dynamic>;
        expect(data['release_count'], 0);
        expect(data['platforms'], isEmpty);
      });
    });
  });
}

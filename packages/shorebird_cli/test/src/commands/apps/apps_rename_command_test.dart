import 'dart:convert';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/apps/apps.dart';
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
  group(AppsRenameCommand, () {
    const appId = 'app-id';
    const oldName = 'Acme Mobile';
    const newName = 'Acme Consumer';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final app = AppMetadata(
      appId: appId,
      displayName: oldName,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late AppsRenameCommand command;

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
      when(() => argResults['name']).thenReturn(newName);

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
        () => codePushClientWrapper.updateApp(
          appId: any(named: 'appId'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) async => {});

      command = runWithOverrides(AppsRenameCommand.new)
        ..testArgResults = argResults;
    });

    test('name and description are correct', () {
      expect(command.name, 'rename');
      expect(command.description, startsWith("Changes an app's display name."));
    });

    test('renames the app', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(
        () => codePushClientWrapper.updateApp(
          appId: appId,
          displayName: newName,
        ),
      ).called(1);
      verify(
        () => logger.success('Renamed "$oldName" to "$newName".'),
      ).called(1);
    });

    group('when preconditions fail', () {
      test('returns the precondition exit code', () async {
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
            checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          ),
        ).thenThrow(
          UserNotAuthorizedException(),
        );
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.noUser.code));
      });
    });

    group('when the new name is blank', () {
      setUp(() => when(() => argResults['name']).thenReturn('   '));

      test('exits with usage and does not write', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNever(
          () => codePushClientWrapper.updateApp(
            appId: any(named: 'appId'),
            displayName: any(named: 'displayName'),
          ),
        );
      });

      test('emits a JSON error envelope in --json mode', () async {
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

    group('when the new name is too long', () {
      setUp(() {
        when(() => argResults['name']).thenReturn(
          'a' * (CommonArguments.appDisplayNameMaxLength + 1),
        );
      });

      test('exits with usage and does not write', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNever(
          () => codePushClientWrapper.updateApp(
            appId: any(named: 'appId'),
            displayName: any(named: 'displayName'),
          ),
        );
      });
    });

    group('when the name is unchanged', () {
      setUp(() => when(() => argResults['name']).thenReturn(oldName));

      test('exits with usage and does not write', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verifyNever(
          () => codePushClientWrapper.updateApp(
            appId: any(named: 'appId'),
            displayName: any(named: 'displayName'),
          ),
        );
      });

      test('emits a JSON error envelope in --json mode', () async {
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

    group('when the rename fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.updateApp(
            appId: any(named: 'appId'),
            displayName: any(named: 'displayName'),
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

    group('when the fetch fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
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
      test('emits from_name and to_name', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runWithOverrides(command.run, jsonMode: true),
          captured: captured,
        );
        expect(result, equals(ExitCode.success.code));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(decoded['status'], 'success');
        final data = decoded['data'] as Map<String, dynamic>;
        expect(data['app_id'], appId);
        expect(data['from_name'], oldName);
        expect(data['to_name'], newName);
      });
    });
  });
}

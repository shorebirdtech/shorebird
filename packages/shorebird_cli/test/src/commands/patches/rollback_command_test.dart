import 'dart:convert';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patches/rollback_command.dart';
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
  group(RollbackCommand, () {
    const appId = 'app-id';
    const releaseVersion = '1.0.0';
    const patchNumber = 1;
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final release = Release(
      id: 0,
      appId: appId,
      version: releaseVersion,
      flutterRevision: 'flutter-revision',
      flutterVersion: 'flutter-version',
      displayName: releaseVersion,
      platformStatuses: const {ReleasePlatform.android: ReleaseStatus.active},
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    const activePatch = ReleasePatch(
      id: 0,
      number: patchNumber,
      channel: 'stable',
      isRolledBack: false,
      artifacts: [],
    );
    const rolledBackPatch = ReleasePatch(
      id: 0,
      number: patchNumber,
      channel: 'stable',
      isRolledBack: true,
      artifacts: [],
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late RollbackCommand command;

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
      ).thenAnswer((_) async => [activePatch]);
      when(
        () => codePushClientWrapper.rollbackPatch(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          patchId: any(named: 'patchId'),
          patchNumber: any(named: 'patchNumber'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(RollbackCommand.new)
        ..testArgResults = argResults;
    });

    test('name is correct', () {
      expect(command.name, 'rollback');
    });

    test('has correct description', () {
      expect(
        command.description,
        startsWith('Rolls back a patch on a release'),
      );
    });

    group('when validation fails', () {
      final exception = ShorebirdNotInitializedException();

      setUp(() {
        when(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
            checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          ),
        ).thenThrow(exception);
      });

      test('exits with exit code from validation error', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(exception.exitCode.code));
      });
    });

    group('when --app-id is provided', () {
      setUp(() {
        when(() => argResults['app-id']).thenReturn('explicit-app-id');
      });

      test('does not require shorebird.yaml', () async {
        await runWithOverrides(command.run);
        verify(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: true,
          ),
        ).called(1);
      });

      test('uses the explicit app id', () async {
        await runWithOverrides(command.run);
        verify(
          () => codePushClientWrapper.getRelease(
            appId: 'explicit-app-id',
            releaseVersion: releaseVersion,
          ),
        ).called(1);
      });
    });

    group('when no matching patch is found', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getReleasePatches(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
          ),
        ).thenAnswer(
          (_) async => [
            const ReleasePatch(
              id: 99,
              number: patchNumber + 1,
              channel: 'stable',
              isRolledBack: false,
              artifacts: [],
            ),
          ],
        );
      });

      test('exits with usage error', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err('No patch found with number $patchNumber'),
        ).called(1);
      });
    });

    group('when patch is already rolled back', () {
      setUp(() {
        when(
          () => codePushClientWrapper.getReleasePatches(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
          ),
        ).thenAnswer((_) async => [rolledBackPatch]);
      });

      test('exits with usage error and does not POST', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err('Patch $patchNumber is already rolled back'),
        ).called(1);
        verifyNever(
          () => codePushClientWrapper.rollbackPatch(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            patchId: any(named: 'patchId'),
            patchNumber: any(named: 'patchNumber'),
          ),
        );
      });
    });

    group('when patch is rolled back successfully', () {
      test('calls rollbackPatch and logs success', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => codePushClientWrapper.rollbackPatch(
            appId: appId,
            releaseId: release.id,
            patchId: activePatch.id,
            patchNumber: patchNumber,
          ),
        ).called(1);
        verify(
          () => logger.success(
            'Patch $patchNumber on release $releaseVersion '
            'has been rolled back.',
          ),
        ).called(1);
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

      test('in human-readable mode, rethrows ProcessExit', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          throwsA(isA<ProcessExit>()),
        );
      });

      test('in --json mode, emits fetch_failed envelope', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runScoped(
            command.run,
            values: {
              codePushClientWrapperRef.overrideWith(
                () => codePushClientWrapper,
              ),
              isJsonModeRef.overrideWith(() => true),
              loggerRef.overrideWith(() => logger),
              shorebirdEnvRef.overrideWith(() => shorebirdEnv),
              shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            },
          ),
          captured: captured,
        );
        expect(result, equals(ExitCode.software.code));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(decoded['status'], 'error');
        expect(
          (decoded['error'] as Map<String, dynamic>)['code'],
          'fetch_failed',
        );
      });
    });

    group('when rollbackPatch itself fails', () {
      setUp(() {
        when(
          () => codePushClientWrapper.rollbackPatch(
            appId: any(named: 'appId'),
            releaseId: any(named: 'releaseId'),
            patchId: any(named: 'patchId'),
            patchNumber: any(named: 'patchNumber'),
          ),
        ).thenThrow(ProcessExit(ExitCode.software.code));
      });

      test('in human-readable mode, rethrows ProcessExit', () async {
        await expectLater(
          () => runWithOverrides(command.run),
          throwsA(isA<ProcessExit>()),
        );
      });

      test('in --json mode, emits software_error envelope', () async {
        final captured = <String>[];
        final result = await captureStdout(
          () => runScoped(
            command.run,
            values: {
              codePushClientWrapperRef.overrideWith(
                () => codePushClientWrapper,
              ),
              isJsonModeRef.overrideWith(() => true),
              loggerRef.overrideWith(() => logger),
              shorebirdEnvRef.overrideWith(() => shorebirdEnv),
              shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
            },
          ),
          captured: captured,
        );
        expect(result, equals(ExitCode.software.code));
        final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
        expect(decoded['status'], 'error');
        expect(
          (decoded['error'] as Map<String, dynamic>)['code'],
          'software_error',
        );
      });
    });

    group('--json', () {
      R runJsonMode<R>(R Function() body) {
        return runScoped(
          body,
          values: {
            codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
            isJsonModeRef.overrideWith(() => true),
            loggerRef.overrideWith(() => logger),
            shorebirdEnvRef.overrideWith(() => shorebirdEnv),
            shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
          },
        );
      }

      test(
        'emits JSON success with release_version, patch_number, action',
        () async {
          final captured = <String>[];
          final result = await captureStdout(
            () => runJsonMode(command.run),
            captured: captured,
          );
          expect(result, equals(ExitCode.success.code));
          expect(captured, hasLength(1));
          final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
          expect(decoded['status'], 'success');
          final data = decoded['data'] as Map<String, dynamic>;
          expect(data['release_version'], releaseVersion);
          expect(data['patch_number'], patchNumber);
          expect(data['action'], 'rollback');
        },
      );

      group('when patch is already rolled back', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleasePatches(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
            ),
          ).thenAnswer((_) async => [rolledBackPatch]);
        });

        test('emits usage_error envelope', () async {
          final captured = <String>[];
          final result = await captureStdout(
            () => runJsonMode(command.run),
            captured: captured,
          );
          expect(result, equals(ExitCode.usage.code));
          final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
          expect(decoded['status'], 'error');
          expect(
            (decoded['error'] as Map<String, dynamic>)['code'],
            'usage_error',
          );
        });
      });

      group('when no patch with the given number exists', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleasePatches(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
            ),
          ).thenAnswer(
            (_) async => [
              const ReleasePatch(
                id: 99,
                number: patchNumber + 1,
                channel: 'stable',
                isRolledBack: false,
                artifacts: [],
              ),
            ],
          );
        });

        test('emits usage_error envelope', () async {
          final captured = <String>[];
          final result = await captureStdout(
            () => runJsonMode(command.run),
            captured: captured,
          );
          expect(result, equals(ExitCode.usage.code));
          final decoded = jsonDecode(captured.first) as Map<String, dynamic>;
          expect(decoded['status'], 'error');
          expect(
            (decoded['error'] as Map<String, dynamic>)['code'],
            'usage_error',
          );
        });
      });
    });
  });
}

import 'dart:convert';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patches/patches_info_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  group(PatchesInfoCommand, () {
    const appId = 'test-app-id';
    const releaseVersion = '1.0.0+1';
    const releaseId = 42;
    const patchNumber = 3;
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    final release = Release(
      id: releaseId,
      appId: appId,
      version: releaseVersion,
      flutterRevision: 'abc123',
      flutterVersion: '3.27.0',
      displayName: releaseVersion,
      platformStatuses: const {ReleasePlatform.android: ReleaseStatus.active},
      createdAt: DateTime(2026, 1, 15),
      updatedAt: DateTime(2026, 1, 16),
    );
    const patch = ReleasePatch(
      id: 10,
      number: patchNumber,
      channel: 'stable',
      isRolledBack: false,
      artifacts: [],
      notes: 'A test patch.',
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late Progress progress;
    late PatchesInfoCommand command;

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
      progress = MockProgress();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdValidator = MockShorebirdValidator();
      command = runWithOverrides(PatchesInfoCommand.new)
        ..testArgResults = argResults;

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => argResults.wasParsed(any())).thenReturn(false);
      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['app-id']).thenReturn(null);
      when(() => argResults['flavor']).thenReturn(null);
      when(() => argResults['release-version']).thenReturn(releaseVersion);
      when(
        () => argResults['patch-number'],
      ).thenReturn(patchNumber.toString());
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async {});
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
    });

    test('has correct name', () {
      expect(command.name, 'info');
    });

    test('has correct description', () {
      expect(
        command.description,
        startsWith('Show details for a specific patch.'),
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

      test('returns the precondition failure exit code', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(exception.exitCode.code));
      });
    });

    group('when --app-id is provided', () {
      setUp(() {
        when(() => argResults['app-id']).thenReturn('explicit-app-id');
      });

      test('does not require shorebird to be initialized', () async {
        await runWithOverrides(command.run);
        verify(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: true,
          ),
        ).called(1);
      });

      test('fetches patches for the explicit app id', () async {
        await runWithOverrides(command.run);
        verify(
          () => codePushClientWrapper.getRelease(
            appId: 'explicit-app-id',
            releaseVersion: releaseVersion,
          ),
        ).called(1);
      });
    });

    group('when --app-id is not provided', () {
      test('requires shorebird to be initialized', () async {
        await runWithOverrides(command.run);
        verify(
          () => shorebirdValidator.validatePreconditions(
            checkUserIsAuthenticated: true,
            checkShorebirdInitialized: true,
          ),
        ).called(1);
      });

      test('fetches patches using app id from shorebird.yaml', () async {
        await runWithOverrides(command.run);
        verify(
          () => codePushClientWrapper.getRelease(
            appId: appId,
            releaseVersion: releaseVersion,
          ),
        ).called(1);
      });

      group('when --flavor is provided', () {
        const flavor = 'staging';
        const flavoredAppId = 'flavored-app-id';
        const flavoredYaml = ShorebirdYaml(
          appId: appId,
          flavors: {flavor: flavoredAppId},
        );

        setUp(() {
          when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(flavoredYaml);
          when(() => argResults['flavor']).thenReturn(flavor);
          when(() => argResults.wasParsed('flavor')).thenReturn(true);
          when(
            () => codePushClientWrapper.getRelease(
              appId: flavoredAppId,
              releaseVersion: releaseVersion,
            ),
          ).thenAnswer((_) async => release);
        });

        test('fetches patches for the flavored app id', () async {
          await runWithOverrides(command.run);
          verify(
            () => codePushClientWrapper.getRelease(
              appId: flavoredAppId,
              releaseVersion: releaseVersion,
            ),
          ).called(1);
        });
      });
    });

    group('when the patch number is not found', () {
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
              number: 99,
              channel: 'stable',
              isRolledBack: false,
              artifacts: [],
            ),
          ],
        );
      });

      test('prints an error and returns usage exit code', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            any(that: contains('No patch found with number $patchNumber')),
          ),
        ).called(1);
        verify(
          () => logger.info(any(that: contains('Available patches'))),
        ).called(1);
      });
    });

    group('human-readable output', () {
      test('prints patch fields', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(() => logger.info(any(that: contains('10')))).called(
          greaterThanOrEqualTo(1),
        );
        verify(
          () => logger.info(any(that: contains('$patchNumber'))),
        ).called(greaterThanOrEqualTo(1));
        verify(() => logger.info(any(that: contains('stable')))).called(1);
        verify(
          () => logger.info(any(that: contains('A test patch.'))),
        ).called(1);
      });

      group('when patch has artifacts', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleasePatches(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
            ),
          ).thenAnswer(
            (_) async => [
              ReleasePatch(
                id: 10,
                number: patchNumber,
                channel: 'stable',
                isRolledBack: false,
                artifacts: [
                  PatchArtifact(
                    id: 1,
                    patchId: 10,
                    arch: 'arm64-v8a',
                    platform: ReleasePlatform.android,
                    hash: 'abc123',
                    size: 1258291,
                    createdAt: DateTime(2026, 1, 15),
                  ),
                ],
              ),
            ],
          );
        });

        test('prints artifact platform, arch, and size', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verify(
            () => logger.info(any(that: contains('Artifacts:'))),
          ).called(1);
          verify(
            () => logger.info(
              any(
                that: allOf(
                  contains('android'),
                  contains('arm64-v8a'),
                ),
              ),
            ),
          ).called(1);
        });
      });

      group('when notes is null', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleasePatches(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
            ),
          ).thenAnswer(
            (_) async => [
              const ReleasePatch(
                id: 10,
                number: patchNumber,
                channel: 'stable',
                isRolledBack: false,
                artifacts: [],
              ),
            ],
          );
        });

        test('does not print Notes line', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.success.code));
          verifyNever(() => logger.info(any(that: contains('Notes:'))));
        });
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

      test('emits JSON success with patch details', () async {
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
        expect(data['patch'], isA<Map<String, dynamic>>());
        final patchData = data['patch'] as Map<String, dynamic>;
        expect(patchData['number'], patchNumber);
      });

      group('when the patch number is not found', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleasePatches(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
            ),
          ).thenAnswer((_) async => []);
        });

        test('emits JSON error envelope and returns usage exit code', () async {
          final captured = <String>[];
          final result = await captureStdout(
            () => runJsonMode(command.run),
            captured: captured,
          );
          expect(result, equals(ExitCode.usage.code));
          expect(captured, hasLength(1));
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

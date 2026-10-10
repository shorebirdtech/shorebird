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

// Shared behavior is tested in patch_rollback_state_command_test.dart; this
// covers only what is specific to rollback.
void main() {
  group(RollbackCommand, () {
    const appId = 'app-id';
    const releaseVersion = '1.0.0';
    const patchNumber = 1;
    final release = Release(
      id: 7,
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
      id: 42,
      number: patchNumber,
      channel: 'stable',
      isRolledBack: false,
      artifacts: [],
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late RollbackCommand command;

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

    Future<({int exitCode, Map<String, dynamic> json})> runJson() =>
        captureJson(() => runWithOverrides(command.run, jsonMode: true));

    Future<bool> anyRollback() => codePushClientWrapper.rollbackPatch(
      appId: any(named: 'appId'),
      releaseId: any(named: 'releaseId'),
      patchId: any(named: 'patchId'),
      patchNumber: any(named: 'patchNumber'),
    );

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
      when(() => argResults['patch-number']).thenReturn('$patchNumber');
      when(() => argResults['require-change']).thenReturn(false);
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => shorebirdEnv.getShorebirdYaml(),
      ).thenReturn(const ShorebirdYaml(appId: appId));
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
      when(anyRollback).thenAnswer((_) async => true);

      command = runWithOverrides(RollbackCommand.new)
        ..testArgResults = argResults;
    });

    test('has rollback name, description and help', () {
      expect(command.name, 'rollback');
      expect(
        command.description,
        startsWith('Rolls back a patch on a release.\n\n'),
      );
      expect(command.description, contains('has been rolled back.'));
      expect(command.description, contains('Rolled back: yes'));
      expect(
        command.argParser.options['patch-number']!.help,
        'The patch number to roll back (e.g. "1").',
      );
      expect(
        command.argParser.options['require-change']!.help,
        startsWith(
          'Exit with a non-zero status if the patch is already '
          'rolled back.',
        ),
      );
    });

    test('calls rollbackPatch and reports the patch as rolled back', () async {
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
          'Patch $patchNumber on release $releaseVersion has been rolled back.',
        ),
      ).called(1);
      verify(() => logger.info('Rolled back: yes')).called(1);
    });

    test(
      'in --json mode, reports action rollback and a rolled-back patch',
      () async {
        final (:exitCode, :json) = await runJson();
        expect(exitCode, equals(ExitCode.success.code));
        final data = json['data'] as Map<String, dynamic>;
        expect(data['action'], 'rollback');
        expect(
          data['patch'],
          equals(activePatch.copyWith(isRolledBack: true).toJson()),
        );
      },
    );

    group('when the patch is already rolled back', () {
      setUp(() {
        when(anyRollback).thenAnswer((_) async => false);
        when(() => argResults['require-change']).thenReturn(true);
      });

      test('says so', () async {
        await runWithOverrides(command.run);
        verify(
          () => logger.err('Patch $patchNumber is already rolled back'),
        ).called(1);
      });

      test('in --json mode, says so', () async {
        final (:exitCode, :json) = await runJson();
        expect(exitCode, equals(ExitCode.usage.code));
        expect(
          (json['error'] as Map<String, dynamic>)['message'],
          'Patch $patchNumber is already rolled back.',
        );
      });
    });

    test('in --json mode, names rollback when the call fails', () async {
      when(anyRollback).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await runJson();
      expect(exitCode, equals(ExitCode.software.code));
      expect(
        (json['error'] as Map<String, dynamic>)['message'],
        'Failed to roll back patch $patchNumber of release "$releaseVersion".',
      );
    });
  });
}

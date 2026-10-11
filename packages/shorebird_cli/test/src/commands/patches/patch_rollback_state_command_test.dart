import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patches/patch_rollback_state_command.dart';
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

/// The arguments a [_TestCommand] passed to [_TestCommand.changePatchState].
typedef _ChangeCall = ({
  String appId,
  int releaseId,
  int patchId,
  int patchNumber,
});

/// A [PatchRollbackStateCommand] that isn't either real command, so these
/// tests cover only the shared behavior.
class _TestCommand extends PatchRollbackStateCommand {
  final calls = <_ChangeCall>[];
  Future<bool> Function() onChange = () async => true;

  @override
  String get name => 'flip';

  @override
  bool get targetIsRolledBack => true;

  @override
  String get verb => 'flip';

  @override
  String get pastParticiple => 'flipped';

  @override
  String get descriptionLead => 'Flips a patch.';

  @override
  String get requireChangeHelp => 'Fail if already flipped.';

  @override
  String alreadyInStateMessage(int patchNumber) =>
      'Patch $patchNumber is already flipped.';

  @override
  Future<bool> changePatchState({
    required String appId,
    required int releaseId,
    required int patchId,
    required int patchNumber,
  }) {
    calls.add((
      appId: appId,
      releaseId: releaseId,
      patchId: patchId,
      patchNumber: patchNumber,
    ));
    return onChange();
  }
}

void main() {
  group(PatchRollbackStateCommand, () {
    const appId = 'app-id';
    const releaseVersion = '1.0.0';
    const patchNumber = 1;
    const shorebirdYaml = ShorebirdYaml(appId: appId);
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
    const patch = ReleasePatch(
      id: 42,
      number: patchNumber,
      channel: 'stable',
      isRolledBack: false,
      artifacts: [],
    );
    const otherPatch = ReleasePatch(
      id: 99,
      number: patchNumber + 1,
      channel: 'stable',
      isRolledBack: false,
      artifacts: [],
    );

    late ArgResults argResults;
    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdValidator shorebirdValidator;
    late ShorebirdLogger logger;
    late _TestCommand command;

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

    void stubPatches(List<ReleasePatch> patches) {
      when(
        () => codePushClientWrapper.getReleasePatches(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
        ),
      ).thenAnswer((_) async => patches);
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
      when(() => argResults['require-change']).thenReturn(false);

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
      stubPatches([patch]);

      command = runWithOverrides(_TestCommand.new)..testArgResults = argResults;
    });

    group('options', () {
      test('adds release, patch, app scope and require-change options', () {
        expect(
          command.argParser.options.keys,
          containsAll([
            'release-version',
            'patch-number',
            'app-id',
            'flavor',
            'require-change',
          ]),
        );
        expect(
          command.argParser.options['patch-number']!.help,
          'The patch number to flip (e.g. "1").',
        );
        expect(
          command.argParser.options['require-change']!.help,
          'Fail if already flipped.',
        );
      });

      test('description is built from the subclass wording', () {
        expect(command.description, startsWith('Flips a patch.\n\n'));
        expect(
          command.description,
          contains('Patch 1 on release 1.0.0+1 has been flipped.'),
        );
        expect(command.description, contains('Rolled back: yes'));
        expect(command.description, contains('shorebird patches flip '));
      });
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
        expect(command.calls, isEmpty);
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
        expect(command.calls.single.appId, 'explicit-app-id');
      });
    });

    group('when --patch-number is not an integer', () {
      setUp(() {
        when(() => argResults['patch-number']).thenReturn('one');
      });

      test('exits with usage error and does not fetch', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err('"one" is not a valid patch number.'),
        ).called(1);
        verifyNever(
          () => codePushClientWrapper.getRelease(
            appId: any(named: 'appId'),
            releaseVersion: any(named: 'releaseVersion'),
          ),
        );
      });

      test('in --json mode, emits usage_error envelope', () async {
        final (:exitCode, :json) = await runJson();
        expect(exitCode, equals(ExitCode.usage.code));
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], 'usage_error');
        expect(error['message'], '"one" is not a valid patch number.');
      });
    });

    group('when no matching patch is found', () {
      setUp(() => stubPatches([otherPatch]));

      test('exits with usage error and lists available patches', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.usage.code));
        verify(
          () => logger.err(
            'No patch found with number $patchNumber '
            'for release "$releaseVersion".',
          ),
        ).called(1);
        verify(
          () => logger.info('Available patches: ${otherPatch.number}.'),
        ).called(1);
        expect(command.calls, isEmpty);
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

      test('in --json mode, emits fetch_failed envelope', () async {
        final (:exitCode, :json) = await runJson();
        expect(exitCode, equals(ExitCode.software.code));
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], 'fetch_failed');
        expect(
          error['message'],
          'Failed to fetch patches for release "$releaseVersion".',
        );
      });
    });

    group('when changing the patch state fails', () {
      setUp(() {
        command.onChange = () => throw ProcessExit(ExitCode.software.code);
      });

      test('in --json mode, emits software_error envelope', () async {
        final (:exitCode, :json) = await runJson();
        expect(exitCode, equals(ExitCode.software.code));
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], 'software_error');
        expect(
          error['message'],
          'Failed to flip patch $patchNumber of release "$releaseVersion".',
        );
      });
    });

    group('when the patch state changes', () {
      test('changes the found patch and logs success', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        expect(command.calls, [
          (
            appId: appId,
            releaseId: release.id,
            patchId: patch.id,
            patchNumber: patchNumber,
          ),
        ]);
        verify(
          () => logger.success(
            'Patch $patchNumber on release $releaseVersion has been flipped.',
          ),
        ).called(1);
      });

      test('prints the patch details in the target state', () async {
        await runWithOverrides(command.run);
        verify(() => logger.info('ID:          ${patch.id}')).called(1);
        verify(() => logger.info('Number:      $patchNumber')).called(1);
        verify(() => logger.info('Rolled back: yes')).called(1);
      });

      test('succeeds with --require-change', () async {
        when(() => argResults['require-change']).thenReturn(true);
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
      });

      test('in --json mode, emits a success envelope', () async {
        final (:exitCode, :json) = await runJson();
        expect(exitCode, equals(ExitCode.success.code));
        expect(json['status'], 'success');
        final data = json['data'] as Map<String, dynamic>;
        expect(data['app_id'], appId);
        expect(data['release_version'], releaseVersion);
        expect(data['patch_number'], patchNumber);
        expect(data['action'], 'flip');
        expect(data['changed'], isTrue);
        expect(
          data['patch'],
          equals(patch.copyWith(isRolledBack: true).toJson()),
        );
      });
    });

    group('when the patch was already in the target state at read time', () {
      setUp(() => stubPatches([patch.copyWith(isRolledBack: true)]));

      test('still asks the server and lets it decide', () async {
        await runWithOverrides(command.run);
        expect(command.calls, hasLength(1));
      });
    });

    group('when the server reports no change', () {
      setUp(() {
        command.onChange = () async => false;
      });

      test('exits successfully and reports the patch state', () async {
        final result = await runWithOverrides(command.run);
        expect(result, equals(ExitCode.success.code));
        verify(
          () => logger.info('Patch $patchNumber is already flipped.'),
        ).called(1);
        verify(() => logger.info('Rolled back: yes')).called(1);
        verifyNever(() => logger.success(any()));
      });

      test('in --json mode, emits success with changed: false', () async {
        final (:exitCode, :json) = await runJson();
        expect(exitCode, equals(ExitCode.success.code));
        final data = json['data'] as Map<String, dynamic>;
        expect(data['changed'], isFalse);
      });

      group('when --require-change is passed', () {
        setUp(() {
          when(() => argResults['require-change']).thenReturn(true);
        });

        test('exits with usage error', () async {
          final result = await runWithOverrides(command.run);
          expect(result, equals(ExitCode.usage.code));
          verify(
            () => logger.err('Patch $patchNumber is already flipped.'),
          ).called(1);
        });

        test('in --json mode, emits usage_error envelope', () async {
          final (:exitCode, :json) = await runJson();
          expect(exitCode, equals(ExitCode.usage.code));
          final error = json['error'] as Map<String, dynamic>;
          expect(error['code'], 'usage_error');
          expect(error['message'], 'Patch $patchNumber is already flipped.');
        });
      });
    });
  });
}

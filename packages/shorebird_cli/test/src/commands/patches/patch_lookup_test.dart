import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patches/patch_lookup.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

class _TestCommand extends ShorebirdCommand with PatchLookup {
  @override
  String get name => 'lookup';

  @override
  String get description => 'Looks up patches.';

  @override
  Future<int> run() async => ExitCode.success.code;
}

void main() {
  useTempWorkingDirectory();
  group(PatchLookup, () {
    const appId = 'app-id';
    const releaseVersion = '1.0.0+1';
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
    const patches = [
      ReleasePatch(
        id: 42,
        number: 1,
        channel: 'stable',
        isRolledBack: false,
        artifacts: [],
      ),
      ReleasePatch(
        id: 43,
        number: 2,
        channel: 'beta',
        isRolledBack: false,
        artifacts: [],
      ),
    ];

    late CodePushClientWrapper codePushClientWrapper;
    late ShorebirdLogger logger;
    late _TestCommand command;

    R runWithOverrides<R>(R Function() body, {bool jsonMode = false}) {
      return runScoped(
        body,
        values: {
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          isJsonModeRef.overrideWith(() => jsonMode),
          loggerRef.overrideWith(() => logger),
        },
      );
    }

    setUp(() {
      codePushClientWrapper = MockCodePushClientWrapper();
      logger = MockShorebirdLogger();
      command = _TestCommand();

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
      ).thenAnswer((_) async => patches);
    });

    group('fetchReleasePatches', () {
      test('returns the release and its patches', () async {
        final result = await runWithOverrides(
          () => command.fetchReleasePatches(
            appId: appId,
            releaseVersion: releaseVersion,
          ),
        );

        expect(result.release, equals(release));
        expect(result.patches, equals(patches));
        expect(result.errorCode, isNull);
        verify(
          () => codePushClientWrapper.getRelease(
            appId: appId,
            releaseVersion: releaseVersion,
          ),
        ).called(1);
        verify(
          () => codePushClientWrapper.getReleasePatches(
            appId: appId,
            releaseId: release.id,
          ),
        ).called(1);
      });

      group('when the fetch fails', () {
        setUp(() {
          when(
            () => codePushClientWrapper.getReleasePatches(
              appId: any(named: 'appId'),
              releaseId: any(named: 'releaseId'),
            ),
          ).thenThrow(ProcessExit(ExitCode.software.code));
        });

        test('reports fetch_failed in --json mode', () async {
          final (:exitCode, :json) = await captureJson(() async {
            final result = await runWithOverrides(
              () => command.fetchReleasePatches(
                appId: appId,
                releaseVersion: releaseVersion,
              ),
              jsonMode: true,
            );
            expect(result.release, isNull);
            expect(result.patches, isEmpty);
            return result.errorCode!;
          });

          expect(exitCode, equals(ExitCode.software.code));
          expect(json['status'], equals('error'));
          final error = json['error'] as Map<String, dynamic>;
          expect(error['code'], equals('fetch_failed'));
          expect(
            error['message'],
            equals('Failed to fetch patches for release "$releaseVersion".'),
          );
        });

        test('uses fetchFailedMessage when given', () async {
          final (:exitCode, :json) = await captureJson(() async {
            final result = await runWithOverrides(
              () => command.fetchReleasePatches(
                appId: appId,
                releaseVersion: releaseVersion,
                fetchFailedMessage: 'Custom failure.',
              ),
              jsonMode: true,
            );
            return result.errorCode!;
          });

          expect(exitCode, equals(ExitCode.software.code));
          final error = json['error'] as Map<String, dynamic>;
          expect(error['message'], equals('Custom failure.'));
        });
      });
    });

    group('findPatchOrReport', () {
      test('returns the patch with the given number', () {
        final result = runWithOverrides(
          () => command.findPatchOrReport(
            patches: patches,
            patchNumber: 2,
            releaseVersion: releaseVersion,
          ),
        );

        expect(result.patch, equals(patches[1]));
        expect(result.errorCode, isNull);
        verifyNever(() => logger.err(any()));
      });

      group('when no patch has the number', () {
        test('lists the available patches as the hint', () {
          final result = runWithOverrides(
            () => command.findPatchOrReport(
              patches: patches,
              patchNumber: 5,
              releaseVersion: releaseVersion,
            ),
          );

          expect(result.patch, isNull);
          expect(result.errorCode, equals(ExitCode.usage.code));
          verify(
            () => logger.err(
              'No patch found with number 5 for release "$releaseVersion".',
            ),
          ).called(1);
          verify(() => logger.info('Available patches: 1, 2.')).called(1);
        });

        test('says the release has no patches when there are none', () {
          final result = runWithOverrides(
            () => command.findPatchOrReport(
              patches: const [],
              patchNumber: 5,
              releaseVersion: releaseVersion,
            ),
          );

          expect(result.errorCode, equals(ExitCode.usage.code));
          verify(
            () => logger.err('No patches found for release "$releaseVersion".'),
          ).called(1);
          verifyNever(() => logger.info(any()));
        });

        test('reports the same message and hint in --json mode', () async {
          final (:exitCode, :json) = await captureJson(() async {
            final result = runWithOverrides(
              () => command.findPatchOrReport(
                patches: patches,
                patchNumber: 5,
                releaseVersion: releaseVersion,
              ),
              jsonMode: true,
            );
            expect(result.patch, isNull);
            return result.errorCode!;
          });

          expect(exitCode, equals(ExitCode.usage.code));
          final error = json['error'] as Map<String, dynamic>;
          expect(error['code'], equals('usage_error'));
          expect(
            error['message'],
            equals(
              'No patch found with number 5 for release "$releaseVersion".',
            ),
          );
          expect(error['hint'], equals('Available patches: 1, 2.'));
          verifyNever(() => logger.info(any()));
        });
      });
    });
  });
}

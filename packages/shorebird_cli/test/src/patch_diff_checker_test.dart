import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'mocks.dart';

void main() {
  group(PatchDiffChecker, () {
    const assetsDiffPrettyString = 'assets diff pretty string';
    const nativeDiffPrettyString = 'native diff pretty string';
    final localArtifact = File('local.artifact');
    final releaseArtifact = File('release.artifact');

    late ArchiveDiffer archiveDiffer;
    late FileSetDiff assetsFileSetDiff;
    late FileSetDiff nativeFileSetDiff;
    late http.Client httpClient;
    late ShorebirdLogger logger;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late PatchDiffChecker patchDiffChecker;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          httpClientRef.overrideWith(() => httpClient),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(FileSetDiff.empty());
      registerFallbackValue(FakeBaseRequest());
    });

    setUp(() {
      archiveDiffer = MockArchiveDiffer();
      assetsFileSetDiff = MockFileSetDiff();
      nativeFileSetDiff = MockFileSetDiff();
      httpClient = MockHttpClient();
      logger = MockShorebirdLogger();
      progress = MockProgress();
      shorebirdEnv = MockShorebirdEnv();
      patchDiffChecker = PatchDiffChecker();

      when(() => archiveDiffer.changedFiles(any(), any()))
          .thenAnswer((_) async => FileSetDiff.empty());
      when(() => archiveDiffer.assetsFileSetDiff(any()))
          .thenReturn(assetsFileSetDiff);
      when(() => archiveDiffer.nativeFileSetDiff(any()))
          .thenReturn(nativeFileSetDiff);
      when(() => archiveDiffer.containsPotentiallyBreakingAssetDiffs(any()))
          .thenReturn(false);
      when(() => archiveDiffer.containsPotentiallyBreakingNativeDiffs(any()))
          .thenReturn(false);

      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(const Stream.empty(), HttpStatus.ok),
      );

      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);

      when(() => shorebirdEnv.canAcceptUserInput).thenReturn(true);

      when(() => assetsFileSetDiff.prettyString)
          .thenReturn(assetsDiffPrettyString);
      when(() => nativeFileSetDiff.prettyString)
          .thenReturn(nativeDiffPrettyString);
    });

    group('confirmUnpatchableDiffsIfNecessary', () {
      group('when native diffs are detected', () {
        setUp(() {
          when(
            () => archiveDiffer.containsPotentiallyBreakingNativeDiffs(any()),
          ).thenReturn(true);
        });

        test('logs warning', () async {
          await runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifact: releaseArtifact,
              archiveDiffer: archiveDiffer,
              allowAssetChanges: false,
              allowNativeChanges: false,
            ),
          );

          verify(
            () => logger.warn(
              '''Your app contains native changes, which cannot be applied with a patch.''',
            ),
          ).called(1);
          verify(
            () => logger.info(yellow.wrap(nativeDiffPrettyString)),
          ).called(1);
          verify(
            () => logger.info(
              any(
                that:
                    contains("If you don't know why you're seeing this error"),
              ),
            ),
          ).called(1);
        });

        test('prompts user if allowNativeChanges is false', () async {
          await runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifact: releaseArtifact,
              archiveDiffer: archiveDiffer,
              allowAssetChanges: false,
              allowNativeChanges: false,
            ),
          );

          verify(() => logger.confirm('Continue anyways?')).called(1);
        });

        test('does not prompt user if allowNativeChanges is true', () async {
          await runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifact: releaseArtifact,
              archiveDiffer: archiveDiffer,
              allowAssetChanges: false,
              allowNativeChanges: true,
            ),
          );

          verifyNever(() => logger.confirm('Continue anyways?'));
        });

        test('throws UserCancelledException if user declines to continue',
            () async {
          when(() => logger.confirm(any())).thenReturn(false);

          await expectLater(
            runWithOverrides(
              () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
                localArtifact: localArtifact,
                releaseArtifact: releaseArtifact,
                archiveDiffer: archiveDiffer,
                allowAssetChanges: false,
                allowNativeChanges: false,
              ),
            ),
            throwsA(
              isA<UserCancelledException>(),
            ),
          );

          verify(() => logger.confirm('Continue anyways?')).called(1);
        });

        test('does not prompt when unable to accept user input', () async {
          when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);

          await expectLater(
            () => runWithOverrides(
              () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
                localArtifact: localArtifact,
                releaseArtifact: releaseArtifact,
                archiveDiffer: archiveDiffer,
                allowAssetChanges: false,
                allowNativeChanges: false,
              ),
            ),
            throwsA(isA<UnpatchableChangeException>()),
          );

          verifyNever(() => logger.confirm(any()));
        });
      });

      group('when asset diffs are detected', () {
        setUp(() {
          when(
            () => archiveDiffer.containsPotentiallyBreakingAssetDiffs(any()),
          ).thenReturn(true);
        });

        test('logs warning', () async {
          await runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifact: releaseArtifact,
              archiveDiffer: archiveDiffer,
              allowAssetChanges: false,
              allowNativeChanges: false,
            ),
          );

          verify(
            () => logger.warn(
              '''Your app contains asset changes, which will not be included in the patch.''',
            ),
          ).called(1);
          verify(
            () => logger.info(yellow.wrap(assetsDiffPrettyString)),
          ).called(1);
        });

        test('prompts user if allowAssetChanges is false', () async {
          await runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifact: releaseArtifact,
              archiveDiffer: archiveDiffer,
              allowAssetChanges: false,
              allowNativeChanges: false,
            ),
          );

          verify(() => logger.confirm('Continue anyways?')).called(1);
        });

        test('does not prompt user if allowAssetChanges is true', () async {
          await runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifact: releaseArtifact,
              archiveDiffer: archiveDiffer,
              allowAssetChanges: true,
              allowNativeChanges: false,
            ),
          );

          verifyNever(() => logger.confirm('Continue anyways?'));
        });

        test('throws UserCancelledException if user declines to continue',
            () async {
          when(() => logger.confirm(any())).thenReturn(false);

          await expectLater(
            runWithOverrides(
              () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
                localArtifact: localArtifact,
                releaseArtifact: releaseArtifact,
                archiveDiffer: archiveDiffer,
                allowAssetChanges: false,
                allowNativeChanges: false,
              ),
            ),
            throwsA(isA<UserCancelledException>()),
          );

          verify(() => logger.confirm('Continue anyways?')).called(1);
        });

        test('does not prompt when unable to accept user input', () async {
          when(() => shorebirdEnv.canAcceptUserInput).thenReturn(false);

          await expectLater(
            () => runWithOverrides(
              () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
                localArtifact: localArtifact,
                releaseArtifact: releaseArtifact,
                archiveDiffer: archiveDiffer,
                allowAssetChanges: false,
                allowNativeChanges: false,
              ),
            ),
            throwsA(isA<UnpatchableChangeException>()),
          );

          verifyNever(() => logger.confirm(any()));
        });
      });

      test('returns true if no potentially breaking diffs are detected',
          () async {
        await expectLater(
          runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifact: releaseArtifact,
              archiveDiffer: archiveDiffer,
              allowAssetChanges: false,
              allowNativeChanges: false,
            ),
          ),
          completes,
        );
      });
    });
  });
}

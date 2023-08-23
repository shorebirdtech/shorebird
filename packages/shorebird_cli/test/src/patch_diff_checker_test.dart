import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

class _FakeBaseRequest extends Fake implements http.BaseRequest {}

class _MockArchiveDiffer extends Mock implements ArchiveDiffer {}

class _MockFileSetDiff extends Mock implements FileSetDiff {}

class _MockHttpClient extends Mock implements http.Client {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

void main() {
  group(PatchDiffChecker, () {
    const assetsDiffPrettyString = 'assets diff pretty string';
    const nativeDiffPrettyString = 'native diff pretty string';
    final localArtifact = File('local.artifact');
    final releaseArtifactUrl = Uri.parse('https://example.com');

    late ArchiveDiffer archiveDiffer;
    late FileSetDiff assetsFileSetDiff;
    late FileSetDiff nativeFileSetDiff;
    late http.Client httpClient;
    late Logger logger;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late PatchDiffChecker patchDiffChecker;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(FileSetDiff.empty());
      registerFallbackValue(_FakeBaseRequest());
    });

    setUp(() {
      archiveDiffer = _MockArchiveDiffer();
      assetsFileSetDiff = _MockFileSetDiff();
      nativeFileSetDiff = _MockFileSetDiff();
      httpClient = _MockHttpClient();
      logger = _MockLogger();
      progress = _MockProgress();
      shorebirdEnv = _MockShorebirdEnv();
      patchDiffChecker = PatchDiffChecker(httpClient: httpClient);

      when(() => archiveDiffer.changedFiles(any(), any()))
          .thenReturn(FileSetDiff.empty());
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

      when(() => shorebirdEnv.isRunningOnCI).thenReturn(false);

      when(() => assetsFileSetDiff.prettyString)
          .thenReturn(assetsDiffPrettyString);
      when(() => nativeFileSetDiff.prettyString)
          .thenReturn(nativeDiffPrettyString);
    });

    group('confirmUnpatchableDiffsIfNecessary', () {
      test('throws Exception when release artifact fails to download',
          () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.internalServerError,
            reasonPhrase: 'Internal Server Error',
          ),
        );

        await expectLater(
          runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifactUrl: releaseArtifactUrl,
              archiveDiffer: archiveDiffer,
              force: false,
            ),
          ),
          throwsA(isA<Exception>()),
        );

        verify(() => progress.fail()).called(1);
      });

      group('when native diffs are detected', () {
        setUp(() {
          when(
            () => archiveDiffer.containsPotentiallyBreakingNativeDiffs(any()),
          ).thenReturn(true);
        });

        test('logs warning', () async {
          final result = await runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifactUrl: releaseArtifactUrl,
              archiveDiffer: archiveDiffer,
              force: false,
            ),
          );

          expect(result, isTrue);
          verify(
            () => logger.warn(
              '''The release artifact contains native changes, which cannot be applied with a patch.''',
            ),
          ).called(1);
          verify(
            () => logger.info(yellow.wrap(nativeDiffPrettyString)),
          ).called(1);
        });

        test('prompts user if force is false', () async {
          final result = await runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifactUrl: releaseArtifactUrl,
              archiveDiffer: archiveDiffer,
              force: false,
            ),
          );

          expect(result, isTrue);
          verify(() => logger.confirm('Continue anyways?')).called(1);
        });

        test('does not prompt user if force is true', () async {
          final result = await runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifactUrl: releaseArtifactUrl,
              archiveDiffer: archiveDiffer,
              force: true,
            ),
          );

          expect(result, isTrue);
          verifyNever(() => logger.confirm('Continue anyways?'));
        });

        test('returns false if user declines to continue', () async {
          when(() => logger.confirm(any())).thenReturn(false);

          final result = await runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifactUrl: releaseArtifactUrl,
              archiveDiffer: archiveDiffer,
              force: false,
            ),
          );

          expect(result, isFalse);
          verify(() => logger.confirm('Continue anyways?')).called(1);
        });

        test('does not prompt when running on CI', () async {
          when(() => shorebirdEnv.isRunningOnCI).thenReturn(true);

          await expectLater(
            () => runWithOverrides(
              () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
                localArtifact: localArtifact,
                releaseArtifactUrl: releaseArtifactUrl,
                archiveDiffer: archiveDiffer,
                force: false,
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
          final result = await runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifactUrl: releaseArtifactUrl,
              archiveDiffer: archiveDiffer,
              force: false,
            ),
          );

          expect(result, isTrue);
          verify(
            () => logger.warn(
              '''The release artifact contains asset changes, which will not be included in the patch.''',
            ),
          ).called(1);
          verify(
            () => logger.info(yellow.wrap(assetsDiffPrettyString)),
          ).called(1);
        });

        test('prompts user if force is false', () async {
          final result = await runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifactUrl: releaseArtifactUrl,
              archiveDiffer: archiveDiffer,
              force: false,
            ),
          );

          expect(result, isTrue);
          verify(() => logger.confirm('Continue anyways?')).called(1);
        });

        test('does not prompt user if force is true', () async {
          final result = await runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifactUrl: releaseArtifactUrl,
              archiveDiffer: archiveDiffer,
              force: true,
            ),
          );

          expect(result, isTrue);
          verifyNever(() => logger.confirm('Continue anyways?'));
        });

        test('returns false if user declines to continue', () async {
          when(() => logger.confirm(any())).thenReturn(false);

          final result = await runWithOverrides(
            () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
              localArtifact: localArtifact,
              releaseArtifactUrl: releaseArtifactUrl,
              archiveDiffer: archiveDiffer,
              force: false,
            ),
          );

          expect(result, isFalse);
          verify(() => logger.confirm('Continue anyways?')).called(1);
        });

        test('does not prompt when running on CI', () async {
          when(() => shorebirdEnv.isRunningOnCI).thenReturn(true);

          await expectLater(
            () => runWithOverrides(
              () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
                localArtifact: localArtifact,
                releaseArtifactUrl: releaseArtifactUrl,
                archiveDiffer: archiveDiffer,
                force: false,
              ),
            ),
            throwsA(isA<UnpatchableChangeException>()),
          );

          verifyNever(() => logger.confirm(any()));
        });
      });

      test('returns true if no potentially breaking diffs are detected',
          () async {
        final result = await runWithOverrides(
          () => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
            localArtifact: localArtifact,
            releaseArtifactUrl: releaseArtifactUrl,
            archiveDiffer: archiveDiffer,
            force: false,
          ),
        );

        expect(result, isTrue);
      });
    });
  });
}

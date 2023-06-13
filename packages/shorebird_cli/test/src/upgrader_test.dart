import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/upgrader.dart';
import 'package:test/test.dart';

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  const currentShorebirdRevision = 'revision-1';
  const newerShorebirdRevision = 'revision-2';

  group(Upgrader, () {
    late ShorebirdProcessResult fetchCurrentVersionResult;
    late ShorebirdProcessResult fetchTagsResult;
    late ShorebirdProcessResult fetchLatestVersionResult;
    late ShorebirdProcessResult hardResetResult;
    late ShorebirdProcess shorebirdProcess;
    late Upgrader upgrader;

    setUp(() {
      fetchCurrentVersionResult = _MockProcessResult();
      fetchTagsResult = _MockProcessResult();
      fetchLatestVersionResult = _MockProcessResult();
      hardResetResult = _MockProcessResult();
      shorebirdProcess = _MockShorebirdProcess();
      upgrader = Upgrader(process: shorebirdProcess);

      when(
        () => shorebirdProcess.run(
          'git',
          ['rev-parse', '--verify', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => fetchCurrentVersionResult);
      when(
        () => shorebirdProcess.run(
          'git',
          ['fetch', '--tags'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => fetchTagsResult);
      when(
        () => shorebirdProcess.run(
          'git',
          ['rev-parse', '--verify', '@{upstream}'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => fetchLatestVersionResult);
      when(
        () => shorebirdProcess.run(
          'git',
          ['reset', '--hard', newerShorebirdRevision],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => hardResetResult);

      when(() => fetchCurrentVersionResult.exitCode).thenReturn(0);
      when(() => fetchLatestVersionResult.exitCode).thenReturn(0);
      when(() => hardResetResult.exitCode).thenReturn(0);
      when(
        () => fetchCurrentVersionResult.stdout,
      ).thenReturn(currentShorebirdRevision);
      when(
        () => fetchLatestVersionResult.stdout,
      ).thenReturn(currentShorebirdRevision);
    });

    test('can be instatiated without a process override', () {
      expect(Upgrader.new, returnsNormally);
    });

    group('isUpToDate', () {
      test('handles errors when determining the current version', () async {
        const errorMessage = 'oops';
        when(() => fetchCurrentVersionResult.exitCode).thenReturn(1);
        when(() => fetchCurrentVersionResult.stderr).thenReturn(errorMessage);
        await expectLater(
          () => upgrader.isUpToDate(),
          throwsA(isA<Exception>()),
        );
      });

      test('handles errors when determining the latest version', () async {
        const errorMessage = 'oops';
        when(() => fetchLatestVersionResult.exitCode).thenReturn(1);
        when(() => fetchLatestVersionResult.stderr).thenReturn(errorMessage);
        await expectLater(
          () => upgrader.isUpToDate(),
          throwsA(isA<Exception>()),
        );
      });

      test('returns true when is up to date', () async {
        await expectLater(upgrader.isUpToDate(), completion(isTrue));
      });

      test('returns false when is not up to date', () async {
        when(
          () => fetchLatestVersionResult.stdout,
        ).thenReturn(newerShorebirdRevision);
        await expectLater(upgrader.isUpToDate(), completion(isFalse));
      });
    });

    group('upgrade', () {
      test('handles errors when updating', () async {
        const errorMessage = 'oops';
        when(
          () => fetchLatestVersionResult.stdout,
        ).thenReturn(newerShorebirdRevision);
        when(() => hardResetResult.exitCode).thenReturn(1);
        when(() => hardResetResult.stderr).thenReturn(errorMessage);
        await expectLater(
          () => upgrader.upgrade(),
          throwsA(isA<Exception>()),
        );
      });

      test(
        'updates when newer version exists',
        () async {
          when(
            () => fetchLatestVersionResult.stdout,
          ).thenReturn(newerShorebirdRevision);
          await expectLater(upgrader.upgrade(), completes);
        },
      );

      test(
        'does not update when already on latest version',
        () async {
          await expectLater(upgrader.upgrade(), completes);
        },
      );
    });
  });
}

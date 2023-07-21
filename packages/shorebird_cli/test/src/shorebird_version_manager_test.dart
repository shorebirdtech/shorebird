import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_version_manager.dart';
import 'package:test/test.dart';

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

void main() {
  group(ShorebirdVersionManager, () {
    const currentShorebirdRevision = 'revision-1';
    const newerShorebirdRevision = 'revision-2';

    late ShorebirdProcessResult fetchCurrentVersionResult;
    late ShorebirdProcessResult fetchLatestVersionResult;
    late ShorebirdProcessResult hardResetResult;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdVersionManager shorebirdVersionManager;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          processRef.overrideWith(() => shorebirdProcess),
        },
      );
    }

    setUp(() {
      fetchCurrentVersionResult = _MockProcessResult();
      fetchLatestVersionResult = _MockProcessResult();
      hardResetResult = _MockProcessResult();
      shorebirdProcess = _MockShorebirdProcess();
      shorebirdVersionManager = ShorebirdVersionManager();

      when(
        () => shorebirdProcess.run(
          'git',
          ['rev-parse', '--verify', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => fetchCurrentVersionResult);
      when(
        () => shorebirdProcess.run(
          'git',
          ['rev-parse', '--verify', '@{upstream}'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => fetchLatestVersionResult);
      when(
        () => shorebirdProcess.run(
          'git',
          ['fetch', '--tags'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => _MockProcessResult());
      when(
        () => shorebirdProcess.run(
          'git',
          ['reset', '--hard', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => hardResetResult);

      when(
        () => fetchCurrentVersionResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => fetchCurrentVersionResult.stdout,
      ).thenReturn(currentShorebirdRevision);
      when(
        () => fetchLatestVersionResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(
        () => fetchLatestVersionResult.stdout,
      ).thenReturn(currentShorebirdRevision);
      when(() => hardResetResult.exitCode).thenReturn(ExitCode.success.code);
    });

    group('isShorebirdVersionCurrent', () {
      test('returns true if current and latest git hashes match', () async {
        when(
          () => fetchCurrentVersionResult.stdout,
        ).thenReturn(currentShorebirdRevision);
        when(
          () => fetchLatestVersionResult.stdout,
        ).thenReturn(currentShorebirdRevision);

        expect(
          await runWithOverrides(
            shorebirdVersionManager.isShorebirdVersionCurrent,
          ),
          isTrue,
        );
      });

      test(
        'returns false if current and latest git hashes differ',
        () async {
          when(
            () => fetchCurrentVersionResult.stdout,
          ).thenReturn(currentShorebirdRevision);
          when(
            () => fetchLatestVersionResult.stdout,
          ).thenReturn(newerShorebirdRevision);

          expect(
            await runWithOverrides(
              shorebirdVersionManager.isShorebirdVersionCurrent,
            ),
            isFalse,
          );
        },
      );

      test(
          'throws ProcessException if git command exits with code other than 0',
          () async {
        const errorMessage = 'oh no!';
        when(
          () => fetchCurrentVersionResult.exitCode,
        ).thenReturn(ExitCode.software.code);
        when(() => fetchCurrentVersionResult.stderr).thenReturn(errorMessage);

        expect(
          runWithOverrides(
            shorebirdVersionManager.isShorebirdVersionCurrent,
          ),
          throwsA(
            isA<ProcessException>().having(
              (e) => e.message,
              'message',
              errorMessage,
            ),
          ),
        );
      });
    });

    group('attemptReset', () {
      test('completes when git command exits with code 0', () async {
        expect(
          runWithOverrides(
            () => shorebirdVersionManager.attemptReset(newRevision: 'HEAD'),
          ),
          completes,
        );
      });

      test(
        '''throws ProcessException when git command exits with code other than 0''',
        () async {
          const errorMessage = 'oh no!';
          when(
            () => hardResetResult.exitCode,
          ).thenReturn(ExitCode.software.code);
          when(() => hardResetResult.stderr).thenReturn(errorMessage);

          expect(
            runWithOverrides(
              () => shorebirdVersionManager.attemptReset(newRevision: 'HEAD'),
            ),
            throwsA(
              isA<ProcessException>().having(
                (e) => e.message,
                'message',
                errorMessage,
              ),
            ),
          );
        },
      );
    });
  });
}

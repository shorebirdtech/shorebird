import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(UpdaterTools, () {
    late File releaseArtifact;
    late File patchArtifact;
    late File outputFile;
    late PatchExecutable patchExecutable;
    late ShorebirdArtifacts shorebirdArtifacts;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess shorebirdProcess;

    late UpdaterTools updaterTools;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          patchExecutableRef.overrideWith(() => patchExecutable),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdArtifactsRef.overrideWith(() => shorebirdArtifacts),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      patchExecutable = MockPatchExecutable();
      shorebirdArtifacts = MockShorebirdArtifacts();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdProcess = MockShorebirdProcess();

      final tempDir = Directory.systemTemp.createTempSync();
      releaseArtifact = File('${tempDir.path}/release')..createSync();
      patchArtifact = File('${tempDir.path}/patch')..createSync();
      outputFile = File('${tempDir.path}/output')..createSync();

      when(() => patchExecutable.path).thenReturn('patch_executable');

      when(
        () => shorebirdArtifacts.getArtifactPath(
          artifact: ShorebirdArtifact.updaterTools,
        ),
      ).thenReturn('updater_tools');

      when(() => shorebirdEnv.dartBinaryFile).thenReturn(File('dart'));

      updaterTools = UpdaterTools();
    });

    group('createDiff', () {
      test('throws FileSystemException if release artifact does not exist',
          () async {
        await expectLater(
          runWithOverrides(
            () => updaterTools.createDiff(
              releaseArtifact: File('non_existent_file'),
              patchArtifact: patchArtifact,
              outputFile: outputFile,
            ),
          ),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('throws FileSystemException if patch artifact does not exist',
          () async {
        await expectLater(
          runWithOverrides(
            () => updaterTools.createDiff(
              releaseArtifact: releaseArtifact,
              patchArtifact: File('non_existent_file'),
              outputFile: outputFile,
            ),
          ),
          throwsA(isA<FileSystemException>()),
        );
      });

      group('when diff exits with non-zero code', () {
        setUp(() {
          when(
            () => shorebirdProcess.run(
              any(),
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer(
            (_) async => const ShorebirdProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: '',
            ),
          );
        });

        test('throws exception', () {
          expect(
            () => runWithOverrides(
              () => updaterTools.createDiff(
                releaseArtifact: releaseArtifact,
                patchArtifact: patchArtifact,
                outputFile: outputFile,
              ),
            ),
            throwsA(isA<Exception>()),
          );
        });
      });

      group('when diff exits successfully', () {
        setUp(() {
          when(
            () => shorebirdProcess.run(
              any(),
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer(
            (_) async => const ShorebirdProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
            ),
          );
        });

        test('completes', () {
          expect(
            () => runWithOverrides(
              () => updaterTools.createDiff(
                releaseArtifact: releaseArtifact,
                patchArtifact: patchArtifact,
                outputFile: outputFile,
              ),
            ),
            returnsNormally,
          );

          verify(
            () => shorebirdProcess.run(
              'dart',
              [
                'run',
                'updater_tools',
                'diff',
                '--release=${releaseArtifact.path}',
                '--patch=${patchArtifact.path}',
                '--patch-executable=${patchExecutable.path}',
                '--output=${outputFile.path}',
              ],
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).called(1);
        });
      });
    });
  });
}

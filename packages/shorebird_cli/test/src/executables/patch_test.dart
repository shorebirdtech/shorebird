import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/executables/patch.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('PatchProgram', () {
    late Cache cache;
    late Directory cacheArtifactDirectory;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdProcessResult patchProcessResult;
    late PatchProgram patchProgram;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          cacheRef.overrideWith(() => cache),
          processRef.overrideWith(() => shorebirdProcess),
          patchProgramRef.overrideWith(() => patchProgram),
        },
      );
    }

    setUp(() {
      patchProgram = PatchProgram();
      shorebirdProcess = MockShorebirdProcess();
      when(
        () => shorebirdProcess.run(
          any(that: endsWith('patch')),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer(
        (invocation) async {
          final args = invocation.positionalArguments[1] as List<String>;
          final diffPath = args[2];
          File(diffPath)
            ..createSync(recursive: true)
            ..writeAsStringSync('diff');
          return patchProcessResult;
        },
      );
      patchProcessResult = MockShorebirdProcessResult();
      when(() => patchProcessResult.exitCode).thenReturn(ExitCode.success.code);

      cacheArtifactDirectory = Directory.systemTemp.createTempSync();
      cache = MockCache();
      when(() => cache.getArtifactDirectory(any()))
          .thenReturn(cacheArtifactDirectory);
      when(() => cache.updateAll()).thenAnswer((_) async {});
    });

    test('runs the correct program', () async {
      final tmpDir = Directory.systemTemp.createTempSync();
      final releaseArtifactFile = File(
        p.join(tmpDir.path, 'release_artifact'),
      )..createSync(recursive: true);
      final patchArtifactFile = File(p.join(tmpDir.path, 'patch_artifact'))
        ..createSync(recursive: true);

      await runWithOverrides(
        () => patchProgram.run(
          releaseArtifactPath: releaseArtifactFile.path,
          patchArtifactPath: patchArtifactFile.path,
          diffPath: p.join(tmpDir.path, 'diff.patch'),
        ),
      );

      verify(
        () => shorebirdProcess.run(
          p.join(cacheArtifactDirectory.path, 'patch'),
          any(
            that: containsAllInOrder([
              releaseArtifactFile.path,
              patchArtifactFile.path,
              endsWith('diff.patch'),
            ]),
          ),
        ),
      ).called(1);
    });

    test('throws error when creating diff fails', () async {
      const stdout = 'uh oh';
      const stderr = 'oops something went wrong';
      when(() => patchProcessResult.exitCode).thenReturn(1);
      when(() => patchProcessResult.stderr).thenReturn(stderr);
      when(() => patchProcessResult.stdout).thenReturn(stdout);

      await expectLater(
        () => runWithOverrides(
          () => patchProgram.run(
            releaseArtifactPath: 'release',
            patchArtifactPath: 'patch',
            diffPath: 'diff',
          ),
        ),
        throwsA(
          isA<PatchFailedException>().having(
            (e) => e.toString(),
            'exception',
            'Failed to create diff (exit code 1).\n'
                '  stdout: $stdout\n'
                '  stderr: $stderr',
          ),
        ),
      );
    });
  });
}

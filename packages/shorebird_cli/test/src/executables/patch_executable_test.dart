import 'dart:io' hide Platform;

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('PatchExecutable', () {
    late Cache cache;
    late Directory cacheArtifactDirectory;
    late Platform platform;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdProcessResult patchProcessResult;
    late PatchExecutable patchExecutable;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          cacheRef.overrideWith(() => cache),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
          patchExecutableRef.overrideWith(() => patchExecutable),
        },
      );
    }

    setUp(() {
      patchExecutable = PatchExecutable();
      shorebirdProcess = MockShorebirdProcess();
      platform = MockPlatform();

      when(
        () => shorebirdProcess.run(any(that: endsWith('patch')), any()),
      ).thenAnswer((invocation) async {
        final args = invocation.positionalArguments[1] as List<String>;
        final diffPath = args[2];
        File(diffPath)
          ..createSync(recursive: true)
          ..writeAsStringSync('diff');
        return patchProcessResult;
      });
      patchProcessResult = MockShorebirdProcessResult();
      when(() => patchProcessResult.exitCode).thenReturn(ExitCode.success.code);

      cacheArtifactDirectory = Directory.systemTemp.createTempSync();
      cache = MockCache();
      when(
        () => cache.getArtifactDirectory(any()),
      ).thenReturn(cacheArtifactDirectory);
      when(() => cache.updateAll()).thenAnswer((_) async {});
    });

    test('runs the correct program', () async {
      final tmpDir = Directory.systemTemp.createTempSync();
      final releaseArtifactFile = File(p.join(tmpDir.path, 'release_artifact'))
        ..createSync(recursive: true);
      final patchArtifactFile = File(p.join(tmpDir.path, 'patch_artifact'))
        ..createSync(recursive: true);

      await runWithOverrides(
        () => patchExecutable.run(
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

      when(
        () => shorebirdProcess.run(any(that: endsWith('patch')), any()),
      ).thenAnswer((_) async => patchProcessResult);

      await expectLater(
        () => runWithOverrides(
          () => patchExecutable.run(
            releaseArtifactPath: 'release',
            patchArtifactPath: 'patch',
            diffPath: 'diff',
          ),
        ),
        throwsA(
          isA<PatchFailedException>().having(
            (e) => e.toString(),
            'exception',
            'Failed to create diff (exit code 1). \n'
                '  stdout: $stdout\n'
                '  stderr: $stderr',
          ),
        ),
      );
    });

    group('when the process exits with code -1073741515', () {
      setUp(() {
        const stdout = 'uh oh';
        const stderr = 'oops something went wrong';
        when(() => patchProcessResult.exitCode).thenReturn(-1073741515);
        when(() => patchProcessResult.stderr).thenReturn(stderr);
        when(() => patchProcessResult.stdout).thenReturn(stdout);

        when(
          () => shorebirdProcess.run(any(that: endsWith('patch')), any()),
        ).thenAnswer((_) async => patchProcessResult);
      });

      group('when on windows', () {
        setUp(() {
          when(() => platform.isWindows).thenReturn(true);
        });

        test('throws a missing C++ runtime exception', () async {
          await expectLater(
            () => runWithOverrides(
              () => patchExecutable.run(
                releaseArtifactPath: 'release',
                patchArtifactPath: 'patch',
                diffPath: 'diff',
              ),
            ),
            throwsA(
              isA<PatchFailedException>().having(
                (e) => e.toString(),
                'exception',
                contains(
                  '''This error code indicates that the Microsoft C++ runtime (VCRUNTIME140.dll) could not be found.''',
                ),
              ),
            ),
          );
        });
      });

      group('when not on windows', () {
        setUp(() {
          when(() => platform.isWindows).thenReturn(false);
        });

        test('does not add the Windows specific message', () async {
          await expectLater(
            () => runWithOverrides(
              () => patchExecutable.run(
                releaseArtifactPath: 'release',
                patchArtifactPath: 'patch',
                diffPath: 'diff',
              ),
            ),
            throwsA(
              isA<PatchFailedException>().having(
                (e) => e.toString(),
                'exception',
                isNot(
                  contains(
                    '''This indicates that the Microsoft C++ runtime (VCRUNTIME140.dll) could not be found.''',
                  ),
                ),
              ),
            ),
          );
        });
      });
    });
  });
}

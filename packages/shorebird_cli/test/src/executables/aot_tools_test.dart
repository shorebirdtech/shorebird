import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(AotTools, () {
    late Cache cache;
    late ShorebirdArtifacts shorebirdArtifacts;
    late ShorebirdProcess process;
    late ShorebirdEnv shorebirdEnv;
    late Directory workingDirectory;
    late File dartBinaryFile;
    late AotTools aotTools;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          cacheRef.overrideWith(() => cache),
          processRef.overrideWith(() => process),
          shorebirdArtifactsRef.overrideWith(() => shorebirdArtifacts),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      cache = MockCache();
      process = MockShorebirdProcess();
      shorebirdArtifacts = MockShorebirdArtifacts();
      shorebirdEnv = MockShorebirdEnv();
      dartBinaryFile = File('dart');
      workingDirectory = Directory('aot-tools test');
      aotTools = AotTools();

      when(() => cache.updateAll()).thenAnswer((_) async {});
      when(() => shorebirdEnv.dartBinaryFile).thenReturn(dartBinaryFile);
      when(
        () => shorebirdArtifacts.getArtifactPath(
          artifact: ShorebirdArtifact.aotTools,
        ),
      ).thenReturn('aot-tools.dill');
    });

    group('link', () {
      const base = './path/to/base.aot';
      const patch = './path/to/patch.aot';
      const analyzeSnapshot = './path/to/analyze_snapshot.aot';
      const outputPath = './path/to/out.vmcode';

      test('throws Exception when process exits with non-zero code', () async {
        when(
          () => shorebirdArtifacts.getArtifactPath(
            artifact: ShorebirdArtifact.aotTools,
          ),
        ).thenReturn('aot-tools.dill');
        when(
          () => process.run(
            dartBinaryFile.path,
            any(),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'error',
          ),
        );
        await expectLater(
          () => runWithOverrides(
            () => aotTools.link(
              base: base,
              patch: patch,
              analyzeSnapshot: analyzeSnapshot,
              outputPath: outputPath,
            ),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'exception',
              'Exception: Failed to link: error',
            ),
          ),
        );
      });

      group('when aot-tools is an executable', () {
        const aotToolsPath = 'aot_tools';

        setUp(() {
          when(
            () => shorebirdArtifacts.getArtifactPath(
              artifact: ShorebirdArtifact.aotTools,
            ),
          ).thenReturn(aotToolsPath);
        });

        test('links and exits with code 0', () async {
          when(
            () => process.run(
              aotToolsPath,
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
          await expectLater(
            runWithOverrides(
              () => aotTools.link(
                base: base,
                patch: patch,
                analyzeSnapshot: analyzeSnapshot,
                workingDirectory: workingDirectory.path,
                outputPath: outputPath,
              ),
            ),
            completes,
          );
          verify(
            () => process.run(
              aotToolsPath,
              [
                'link',
                '--base=$base',
                '--patch=$patch',
                '--analyze-snapshot=$analyzeSnapshot',
                '--output=$outputPath',
              ],
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).called(1);
        });
      });

      group('when aot-tools is a kernel file', () {
        const aotToolsPath = 'aot_tools.dill';

        setUp(() {
          when(
            () => shorebirdArtifacts.getArtifactPath(
              artifact: ShorebirdArtifact.aotTools,
            ),
          ).thenReturn(aotToolsPath);
        });

        test('links and exits with code 0', () async {
          when(
            () => process.run(
              dartBinaryFile.path,
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
          await expectLater(
            runWithOverrides(
              () => aotTools.link(
                base: base,
                patch: patch,
                analyzeSnapshot: analyzeSnapshot,
                workingDirectory: workingDirectory.path,
                outputPath: outputPath,
              ),
            ),
            completes,
          );
          verify(
            () => process.run(
              dartBinaryFile.path,
              [
                'run',
                aotToolsPath,
                'link',
                '--base=$base',
                '--patch=$patch',
                '--analyze-snapshot=$analyzeSnapshot',
                '--output=$outputPath',
              ],
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).called(1);
        });
      });

      group('when aot_tools is a dart file', () {
        const aotToolsPath = 'aot_tools.dart';

        setUp(() {
          when(
            () => shorebirdArtifacts.getArtifactPath(
              artifact: ShorebirdArtifact.aotTools,
            ),
          ).thenReturn(aotToolsPath);
        });

        test('links and exits with code 0', () async {
          when(
            () => process.run(
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
          await expectLater(
            runWithOverrides(
              () => aotTools.link(
                base: base,
                patch: patch,
                analyzeSnapshot: analyzeSnapshot,
                workingDirectory: workingDirectory.path,
                outputPath: outputPath,
              ),
            ),
            completes,
          );
          verify(
            () => process.run(
              dartBinaryFile.path,
              [
                'run',
                aotToolsPath,
                'link',
                '--base=$base',
                '--patch=$patch',
                '--analyze-snapshot=$analyzeSnapshot',
                '--output=$outputPath',
              ],
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).called(1);
        });
      });
    });

    group('isGeneratePatchDiffBaseSupported', () {
      var stderr = '';
      setUp(() {
        when(
          () => process.run(
            dartBinaryFile.path,
            any(),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async =>
              ShorebirdProcessResult(exitCode: 1, stdout: '', stderr: stderr),
        );
      });

      group('when dump_blobs flag is not recognized', () {
        setUp(() {
          stderr = 'Could not find a command named "dump_blobs"';
        });

        test('returns false', () async {
          final result = await runWithOverrides(
            () => aotTools.isGeneratePatchDiffBaseSupported(),
          );
          expect(result, isFalse);
        });
      });

      group('when dump_blobs is recognized', () {
        setUp(() {
          stderr = 'Invalid snapshot';
        });

        test('returns true', () async {
          final result = await runWithOverrides(
            () => aotTools.isGeneratePatchDiffBaseSupported(),
          );
          expect(result, isTrue);
        });
      });
    });

    group('generatePatchDiffBase', () {
      setUp(() {
        when(
          () => process.run(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 0,
            stdout: '',
            stderr: 'error',
          ),
        );
      });

      group('when command returns non-zero exit code', () {
        setUp(() {
          when(
            () => process.run(
              any(),
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer(
            (_) async => const ShorebirdProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'error',
            ),
          );
        });

        test('throws exception', () async {
          await expectLater(
            () => runWithOverrides(
              () => aotTools.generatePatchDiffBase(
                releaseSnapshot: File('release_snapshot'),
                analyzeSnapshotPath: 'analyze_snapshot',
              ),
            ),
            throwsA(
              isA<Exception>().having(
                (e) => '$e',
                'exception',
                'Exception: Failed to generate patch diff base: error',
              ),
            ),
          );
        });
      });

      group('when out file does not exist', () {
        setUp(() {
          when(
            () => process.run(
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

        test('throws exception', () async {
          await expectLater(
            () => runWithOverrides(
              () => aotTools.generatePatchDiffBase(
                releaseSnapshot: File('release_snapshot'),
                analyzeSnapshotPath: 'analyze_snapshot',
              ),
            ),
            throwsA(
              isA<Exception>().having(
                (e) => '$e',
                'exception',
                '''Exception: Failed to generate patch diff base: output file does not exist''',
              ),
            ),
          );
        });
      });

      group('when out file is created', () {
        setUp(() {
          when(
            () => process.run(
              any(),
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((invocation) async {
            final outArgument =
                (invocation.positionalArguments.last as List<String>)
                    .firstWhere((String element) => element.startsWith('--out'))
                    .split('=')
                    .last;
            File(outArgument).createSync(recursive: true);
            return const ShorebirdProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
            );
          });
        });

        test('returns path to file', () async {
          final result = await runWithOverrides(
            () => aotTools.generatePatchDiffBase(
              releaseSnapshot: File('release_snapshot'),
              analyzeSnapshotPath: 'analyze_snapshot',
            ),
          );

          expect(result.existsSync(), isTrue);
        });
      });
    });
  });
}

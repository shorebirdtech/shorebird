import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
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
      final base = p.join('.', 'path', 'to', 'base.aot');
      final patch = p.join('.', 'path', 'to', 'patch.aot');
      final analyzeSnapshot = p.join('.', 'path', 'to', 'analyze_snapshot');
      final genSnapshot = p.join('.', 'path', 'to', 'gen_snapshot');
      final kernel = p.join('.', 'path', 'to', 'kernel.dill');
      final outputPath = p.join('.', 'path', 'to', 'out.vmcode');
      final linkJsonPath = p.join('.', 'path', 'to', 'link.jsonl');

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
              genSnapshot: genSnapshot,
              kernel: kernel,
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
                genSnapshot: genSnapshot,
                kernel: kernel,
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

      group(
        'when --dump-debug-info is provided',
        () {
          const aotToolsPath = 'aot_tools';

          setUp(() {
            when(
              () => shorebirdArtifacts.getArtifactPath(
                artifact: ShorebirdArtifact.aotTools,
              ),
            ).thenReturn(aotToolsPath);
          });

          test('forwards the option to aot_tools', () async {
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
                  genSnapshot: genSnapshot,
                  kernel: kernel,
                  workingDirectory: workingDirectory.path,
                  outputPath: outputPath,
                  dumpDebugInfoPath: 'my_debug_path',
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
                  '--dump-debug-info=my_debug_path',
                ],
                workingDirectory: any(named: 'workingDirectory'),
              ),
            ).called(1);
          });
        },
      );

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
                genSnapshot: genSnapshot,
                kernel: kernel,
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
                genSnapshot: genSnapshot,
                kernel: kernel,
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

      group('when when link expects gen_snapshot', () {
        const aotToolsPath = 'aot_tools';

        setUp(() {
          when(
            () => shorebirdArtifacts.getArtifactPath(
              artifact: ShorebirdArtifact.aotTools,
            ),
          ).thenReturn(aotToolsPath);
        });

        test('passes gen_snapshot to aot_tools', () async {
          when(
            () => process.run(
              aotToolsPath,
              ['--version'],
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer(
            (_) async => const ShorebirdProcessResult(
              exitCode: 0,
              stdout: '0.0.1',
              stderr: '',
            ),
          );
          when(
            () => process.run(
              aotToolsPath,
              any(that: contains('--gen-snapshot=$genSnapshot')),
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
                genSnapshot: genSnapshot,
                kernel: kernel,
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
                '--gen-snapshot=$genSnapshot',
                '--kernel=$kernel',
                '--reporter=json',
                '--redirect-to=$linkJsonPath',
              ],
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).called(1);
        });

        test('returns link percentage', () async {
          workingDirectory = Directory.systemTemp.createTempSync();
          when(
            () => process.run(
              aotToolsPath,
              ['--version'],
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((_) async {
            return const ShorebirdProcessResult(
              exitCode: 0,
              stdout: '0.0.1',
              stderr: '',
            );
          });
          when(
            () => process.run(
              aotToolsPath,
              any(that: contains('--gen-snapshot=$genSnapshot')),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer(
            (_) async {
              File(p.join(workingDirectory.path, 'link.jsonl'))
                  .writeAsStringSync(
                '''
{"type":"link_success","base_codes_length":3036,"patch_codes_length":3036,"base_code_size":861816,"patch_code_size":861816,"linked_code_size":860460,"link_percentage":99.8426578295135}
{"type":"link_debug","message":"wrote vmcode file to out.vmcode"}''',
              );
              return const ShorebirdProcessResult(
                exitCode: 0,
                stdout: '',
                stderr: '',
              );
            },
          );
          await expectLater(
            runWithOverrides(
              () => aotTools.link(
                base: base,
                patch: patch,
                analyzeSnapshot: analyzeSnapshot,
                genSnapshot: genSnapshot,
                kernel: kernel,
                workingDirectory: workingDirectory.path,
                outputPath: outputPath,
              ),
            ),
            completion(equals(99.8426578295135)),
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
                '--gen-snapshot=$genSnapshot',
                '--kernel=$kernel',
                '--reporter=json',
                '--redirect-to=$linkJsonPath',
              ],
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).called(1);
        });
      });
    });

    group('isGeneratePatchDiffBaseSupported', () {
      var stdout = '';
      setUp(() {
        when(
          () => process.run(
            dartBinaryFile.path,
            any(),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async => ShorebirdProcessResult(
            exitCode: ExitCode.success.code,
            stdout: stdout,
            stderr: '',
          ),
        );
      });

      group('when dump_blobs flag is not recognized', () {
        setUp(() {
          stdout = '''
Dart equivalent of bintools

Usage: aot_tools <command> [arguments]

Global options:
-h, --help       Print this usage information.
-v, --verbose    Noisy logging.

Available commands:
  link   Link two aot snapshots.

Run "aot_tools help <command>" for more information about a command.
''';
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
          stdout = '''
Dart equivalent of bintools

Usage: aot_tools <command> [arguments]

Global options:
-h, --help            Print this usage information.
-v, --[no-]verbose    Noisy logging.

Available commands:
  dump_blobs              Reads the isolate and vm snapshot data from an aot snapshot file, concatenates them, and writes them to the specified out path.
  dump_linker_overrides   Statically analyzes dart code and dumps the overrides to the specified output path.
  link                    Link two aot snapshots.

Run "aot_tools help <command>" for more information about a command.
''';
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

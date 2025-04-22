import 'dart:convert';
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(AotTools, () {
    late Cache cache;
    late ShorebirdArtifacts shorebirdArtifacts;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdLogger logger;
    late ShorebirdProcess process;
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
          loggerRef.overrideWith(() => logger),
        },
      );
    }

    setUp(() {
      cache = MockCache();
      process = MockShorebirdProcess();
      shorebirdArtifacts = MockShorebirdArtifacts();
      shorebirdEnv = MockShorebirdEnv();
      logger = MockShorebirdLogger();
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

      test('throws exception when process exits with non-zero code', () async {
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
        when(
          () => process.start(
            dartBinaryFile.path,
            any(),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async {
          final mockProcess = MockProcess();
          when(() => mockProcess.exitCode).thenAnswer((_) async => 1);
          when(
            () => mockProcess.stdout,
          ).thenAnswer((_) => Stream.value(utf8.encode('info')));
          when(
            () => mockProcess.stderr,
          ).thenAnswer((_) => Stream.value(utf8.encode('error')));

          return mockProcess;
        });
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
            isA<AotToolsExecutionFailure>().having(
              (e) => '$e',
              'toString',
              contains('''
stdout: info
stderr: error'''),
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
          ).thenAnswer((_) async {
            return const ShorebirdProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
            );
          });
          when(
            () => process.start(
              aotToolsPath,
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((_) async {
            final mockProcess = MockProcess();
            when(() => mockProcess.exitCode).thenAnswer((_) async => 0);
            when(
              () => mockProcess.stdout,
            ).thenAnswer((_) => const Stream.empty());
            when(
              () => mockProcess.stderr,
            ).thenAnswer((_) => const Stream.empty());

            return mockProcess;
          });
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
            () => process.start(aotToolsPath, [
              'link',
              '--base=$base',
              '--patch=$patch',
              '--analyze-snapshot=$analyzeSnapshot',
              '--output=$outputPath',
              '--verbose',
            ], workingDirectory: any(named: 'workingDirectory')),
          ).called(1);
        });

        test('passes additional args to underlying process', () async {
          when(
            () => process.run(
              aotToolsPath,
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((_) async {
            return const ShorebirdProcessResult(
              exitCode: 0,
              stdout: '',
              stderr: '',
            );
          });
          when(
            () => process.start(
              aotToolsPath,
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((_) async {
            final mockProcess = MockProcess();
            when(() => mockProcess.exitCode).thenAnswer((_) async => 0);
            when(
              () => mockProcess.stdout,
            ).thenAnswer((_) => const Stream.empty());
            when(
              () => mockProcess.stderr,
            ).thenAnswer((_) => const Stream.empty());

            return mockProcess;
          });
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
                additionalArgs: ['--foo', 'bar'],
              ),
            ),
            completes,
          );
          verify(
            () => process.start(aotToolsPath, [
              'link',
              '--base=$base',
              '--patch=$patch',
              '--analyze-snapshot=$analyzeSnapshot',
              '--output=$outputPath',
              '--verbose',
              '--',
              '--foo',
              'bar',
            ], workingDirectory: any(named: 'workingDirectory')),
          ).called(1);
        });

        test('forwards stdout from aot_tools link to the logger', () async {
          when(
            () => process.start(
              aotToolsPath,
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((_) async {
            final mockProcess = MockProcess();
            when(() => mockProcess.exitCode).thenAnswer((_) async => 0);
            when(
              () => mockProcess.stdout,
            ).thenAnswer((_) => Stream.value(utf8.encode('stdout')));
            when(
              () => mockProcess.stderr,
            ).thenAnswer((_) => const Stream.empty());

            return mockProcess;
          });

          await runWithOverrides(
            () => aotTools.link(
              base: base,
              patch: patch,
              analyzeSnapshot: analyzeSnapshot,
              genSnapshot: genSnapshot,
              kernel: kernel,
              workingDirectory: workingDirectory.path,
              outputPath: outputPath,
            ),
          );

          // One for --version and one for the link command.
          verify(() => logger.detail('stdout')).called(2);
        });
      });

      group('when --dump-debug-info is provided', () {
        const aotToolsPath = 'aot_tools';

        setUp(() {
          when(
            () => shorebirdArtifacts.getArtifactPath(
              artifact: ShorebirdArtifact.aotTools,
            ),
          ).thenReturn(aotToolsPath);
        });

        test('forwards the option to aot_tools', () async {
          const debugPath = 'my_debug_path';
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
          when(
            () => process.start(
              aotToolsPath,
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((_) async {
            final mockProcess = MockProcess();
            when(() => mockProcess.exitCode).thenAnswer((_) async => 0);
            when(
              () => mockProcess.stdout,
            ).thenAnswer((_) => const Stream.empty());
            when(
              () => mockProcess.stderr,
            ).thenAnswer((_) => const Stream.empty());

            return mockProcess;
          });
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
                dumpDebugInfoPath: debugPath,
              ),
            ),
            completes,
          );
          verify(
            () => process.start(aotToolsPath, [
              'link',
              '--base=$base',
              '--patch=$patch',
              '--analyze-snapshot=$analyzeSnapshot',
              '--output=$outputPath',
              '--verbose',
              '--dump-debug-info=$debugPath',
            ], workingDirectory: any(named: 'workingDirectory')),
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
          when(
            () => process.start(
              dartBinaryFile.path,
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((_) async {
            final mockProcess = MockProcess();
            when(() => mockProcess.exitCode).thenAnswer((_) async => 0);
            when(
              () => mockProcess.stdout,
            ).thenAnswer((_) => const Stream.empty());
            when(
              () => mockProcess.stderr,
            ).thenAnswer((_) => const Stream.empty());
            return mockProcess;
          });
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
            () => process.start(dartBinaryFile.path, [
              'run',
              aotToolsPath,
              'link',
              '--base=$base',
              '--patch=$patch',
              '--analyze-snapshot=$analyzeSnapshot',
              '--output=$outputPath',
              '--verbose',
            ], workingDirectory: any(named: 'workingDirectory')),
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
          when(
            () => process.start(
              any(),
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((_) async {
            final mockProcess = MockProcess();
            when(() => mockProcess.exitCode).thenAnswer((_) async => 0);
            when(
              () => mockProcess.stdout,
            ).thenAnswer((_) => const Stream.empty());
            when(
              () => mockProcess.stderr,
            ).thenAnswer((_) => const Stream.empty());

            return mockProcess;
          });
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
            () => process.start(dartBinaryFile.path, [
              'run',
              aotToolsPath,
              'link',
              '--base=$base',
              '--patch=$patch',
              '--analyze-snapshot=$analyzeSnapshot',
              '--output=$outputPath',
              '--verbose',
            ], workingDirectory: any(named: 'workingDirectory')),
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
            () => process.start(aotToolsPath, [
              '--version',
            ], workingDirectory: any(named: 'workingDirectory')),
          ).thenAnswer((_) async {
            final mockProcess = MockProcess();
            when(() => mockProcess.exitCode).thenAnswer((_) async => 0);
            when(
              () => mockProcess.stdout,
            ).thenAnswer((_) => Stream.value(utf8.encode('0.0.1')));
            when(
              () => mockProcess.stderr,
            ).thenAnswer((_) => const Stream.empty());
            return mockProcess;
          });
          when(
            () => process.start(
              aotToolsPath,
              any(that: contains('--gen-snapshot=$genSnapshot')),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((_) async {
            final mockProcess = MockProcess();
            when(() => mockProcess.exitCode).thenAnswer((_) async => 0);
            when(
              () => mockProcess.stdout,
            ).thenAnswer((_) => const Stream.empty());
            when(
              () => mockProcess.stderr,
            ).thenAnswer((_) => const Stream.empty());

            return mockProcess;
          });
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
            () => process.start(aotToolsPath, [
              'link',
              '--base=$base',
              '--patch=$patch',
              '--analyze-snapshot=$analyzeSnapshot',
              '--output=$outputPath',
              '--verbose',
              '--gen-snapshot=$genSnapshot',
              '--kernel=$kernel',
              '--reporter=json',
              '--redirect-to=$linkJsonPath',
            ], workingDirectory: any(named: 'workingDirectory')),
          ).called(1);
        });

        test('returns link percentage', () async {
          workingDirectory = Directory.systemTemp.createTempSync();
          when(
            () => process.start(aotToolsPath, [
              '--version',
            ], workingDirectory: any(named: 'workingDirectory')),
          ).thenAnswer((_) async {
            final mockProcess = MockProcess();
            when(() => mockProcess.exitCode).thenAnswer((_) async => 0);
            when(
              () => mockProcess.stdout,
            ).thenAnswer((_) => Stream.value(utf8.encode('0.0.1')));
            when(
              () => mockProcess.stderr,
            ).thenAnswer((_) => const Stream.empty());
            return mockProcess;
          });
          when(
            () => process.start(
              aotToolsPath,
              any(that: contains('--gen-snapshot=$genSnapshot')),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((_) async {
            File(p.join(workingDirectory.path, 'link.jsonl')).writeAsStringSync(
              '''
{"type":"link_success","base_codes_length":3036,"patch_codes_length":3036,"base_code_size":861816,"patch_code_size":861816,"linked_code_size":860460,"link_percentage":99.8426578295135}
{"type":"link_debug","message":"wrote vmcode file to out.vmcode"}''',
            );

            final mockProcess = MockProcess();
            when(() => mockProcess.exitCode).thenAnswer((_) async => 0);
            when(
              () => mockProcess.stdout,
            ).thenAnswer((_) => const Stream.empty());
            when(
              () => mockProcess.stderr,
            ).thenAnswer((_) => const Stream.empty());

            return mockProcess;
          });
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
            () => process.start(aotToolsPath, [
              'link',
              '--base=$base',
              '--patch=$patch',
              '--analyze-snapshot=$analyzeSnapshot',
              '--output=$outputPath',
              '--verbose',
              '--gen-snapshot=$genSnapshot',
              '--kernel=$kernel',
              '--reporter=json',
              '--redirect-to=$linkJsonPath',
            ], workingDirectory: any(named: 'workingDirectory')),
          ).called(1);
        });
      });

      group('isLinkDebugInfoSupported', () {
        test('returns true when the argument is present in the help', () async {
          when(
            () => process.start(
              any(),
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((_) async {
            final mockProcess = MockProcess();
            when(() => mockProcess.exitCode).thenAnswer((_) async => 0);
            when(() => mockProcess.stdout).thenAnswer(
              (_) => Stream.value(
                utf8.encode('''
Link two aot snapshots.

Usage: aot_tools link [arguments]
-h, --help                            Print this usage information.
    --base (mandatory)                Path to the base snapshot to link against.
    --patch (mandatory)               Path to the patch snapshot to link.
    --analyze-snapshot (mandatory)    Path to analyze_snapshot binary.
    --gen-snapshot (mandatory)        Path to gen_snapshot binary.
    --kernel (mandatory)              Path to the patch kernel (.dill) file.
    --output (mandatory)              Path to the output vmcode file.
    --enable-asserts                  Whether to enable asserts.
    --linker-overrides                Path to the linker overrides json file.
    --dump-debug-info                 When specified, debug information will be generated and written to the provided path.
    --reporter                        Set how to print link results.

          [json]                      Prints the results in json format.
          [pretty] (default)          Prints the results in a human readable format.

    --redirect-to                     Redirect output to a file.

Run "aot_tools help" to see global options.
'''),
              ),
            );
            when(
              () => mockProcess.stderr,
            ).thenAnswer((_) => const Stream.empty());
            return mockProcess;
          });

          await expectLater(
            runWithOverrides(() => aotTools.isLinkDebugInfoSupported()),
            completion(isTrue),
          );
        });

        test(
          'returns false when the argument is not present in the help',
          () async {
            when(
              () => process.start(
                any(),
                any(),
                workingDirectory: any(named: 'workingDirectory'),
              ),
            ).thenAnswer((_) async {
              final mockProcess = MockProcess();
              when(() => mockProcess.exitCode).thenAnswer((_) async => 0);
              when(() => mockProcess.stdout).thenAnswer(
                (_) => Stream.value(
                  utf8.encode('''
Link two aot snapshots.

Usage: aot_tools link [arguments]
-h, --help                            Print this usage information.
    --base (mandatory)                Path to the base snapshot to link against.
    --patch (mandatory)               Path to the patch snapshot to link.
    --analyze-snapshot (mandatory)    Path to analyze_snapshot binary.
    --gen-snapshot (mandatory)        Path to gen_snapshot binary.
    --kernel (mandatory)              Path to the patch kernel (.dill) file.
    --output (mandatory)              Path to the output vmcode file.
    --enable-asserts                  Whether to enable asserts.
    --linker-overrides                Path to the linker overrides json file.
    --reporter                        Set how to print link results.

          [json]                      Prints the results in json format.
          [pretty] (default)          Prints the results in a human readable format.

    --redirect-to                     Redirect output to a file.

Run "aot_tools help" to see global options.
'''),
                ),
              );
              when(
                () => mockProcess.stderr,
              ).thenAnswer((_) => const Stream.empty());
              return mockProcess;
            });

            await expectLater(
              runWithOverrides(() => aotTools.isLinkDebugInfoSupported()),
              completion(isFalse),
            );
          },
        );
      });
    });

    group('isGeneratePatchDiffBaseSupported', () {
      var stdout = '';
      setUp(() {
        when(
          () => process.start(
            dartBinaryFile.path,
            any(),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async {
          final mockProcess = MockProcess();
          when(() => mockProcess.exitCode).thenAnswer((_) async => 0);
          when(
            () => mockProcess.stdout,
          ).thenAnswer((_) => Stream.value(utf8.encode(stdout)));
          when(
            () => mockProcess.stderr,
          ).thenAnswer((_) => const Stream.empty());
          return mockProcess;
        });
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
      late int exitCode;
      late String stdout;
      late String stderr;

      setUp(() {
        exitCode = 0;
        stdout = '';
        stderr = '';
        when(
          () => process.start(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async {
          final mockProcess = MockProcess();
          when(() => mockProcess.exitCode).thenAnswer((_) async => exitCode);
          when(
            () => mockProcess.stdout,
          ).thenAnswer((_) => Stream.value(utf8.encode(stdout)));
          when(
            () => mockProcess.stderr,
          ).thenAnswer((_) => Stream.value(utf8.encode(stderr)));
          return mockProcess;
        });
      });

      group('when command returns non-zero exit code', () {
        setUp(() {
          exitCode = 1;
          stderr = 'error';
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
              isA<AotToolsExecutionFailure>().having(
                (e) => '$e',
                'toString',
                contains('stderr: error'),
              ),
            ),
          );
        });
      });

      group('when out file does not exist', () {
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
            () => process.start(
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
            final mockProcess = MockProcess();
            when(() => mockProcess.exitCode).thenAnswer((_) async => exitCode);
            when(
              () => mockProcess.stdout,
            ).thenAnswer((_) => Stream.value(utf8.encode(stdout)));
            when(
              () => mockProcess.stderr,
            ).thenAnswer((_) => Stream.value(utf8.encode(stderr)));
            return mockProcess;
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

      group('getLinkMetadata', () {
        late int exitCode;
        late String stdout;
        late String stderr;

        setUp(() {
          stdout = '';
          stderr = '';
          exitCode = 0;
          when(
            () => process.start(
              any(),
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((_) async {
            final mockProcess = MockProcess();
            when(() => mockProcess.exitCode).thenAnswer((_) async => exitCode);
            when(
              () => mockProcess.stdout,
            ).thenAnswer((_) => Stream.value(utf8.encode(stdout)));
            when(
              () => mockProcess.stderr,
            ).thenAnswer((_) => Stream.value(utf8.encode(stderr)));
            return mockProcess;
          });
          when(
            () => process.start(
              any(),
              any(),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((_) async {
            final mockProcess = MockProcess();
            when(() => mockProcess.exitCode).thenAnswer((_) async => exitCode);
            when(
              () => mockProcess.stdout,
            ).thenAnswer((_) => Stream.value(utf8.encode(stdout)));
            when(
              () => mockProcess.stderr,
            ).thenAnswer((_) => Stream.value(utf8.encode(stderr)));
            return mockProcess;
          });
        });

        test('returns link metadata', () async {
          stdout = '{}';
          final result = await runWithOverrides(
            () => aotTools.getLinkMetadata(debugDir: '/debug'),
          );
          expect(result, isA<Map<String, dynamic>>());
        });

        test('throws FormatException when aot_tools outputs invalid json', () async {
          stdout = 'invalid';
          await expectLater(
            () => runWithOverrides(
              () => aotTools.getLinkMetadata(debugDir: '/debug'),
            ),
            throwsFormatException,
          );
        });
      });
    });
  });
}

// cspell:words xcuserdata xcuserdatad
import 'dart:io' hide Platform;

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(Apple, () {
    late AotTools aotTools;
    late Apple apple;
    late Progress progress;
    late TestNativePlatform platform;
    late ShorebirdArtifacts shorebirdArtifacts;
    late ShorebirdLogger logger;
    late ShorebirdEnv shorebirdEnv;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          aotToolsRef.overrideWith(() => aotTools),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          shorebirdArtifactsRef.overrideWith(() => shorebirdArtifacts),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      aotTools = MockAotTools();
      apple = Apple();
      platform = TestNativePlatform(environment: {});
      progress = MockProgress();
      logger = MockShorebirdLogger();
      shorebirdArtifacts = MockShorebirdArtifacts();
      shorebirdEnv = MockShorebirdEnv();

      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => aotTools.getLinkMetadata(
          debugDir: any(named: 'debugDir'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => {'key': 'value'});
    });

    group(MissingXcodeProjectException, () {
      group('ios', () {
        test('toString', () {
          const exception = MissingXcodeProjectException(
            platformFolderPath: 'test_project_path',
            platform: ApplePlatform.ios,
          );
          expect(
            exception.toString(),
            '''
Could not find an Xcode project in test_project_path.
If your project does not support ios, you can safely remove test_project_path.
Otherwise, to repair ios, run "flutter create . --platforms ios"''',
          );
        });
      });

      group('macos', () {
        test('toString', () {
          const exception = MissingXcodeProjectException(
            platformFolderPath: 'test_project_path',
            platform: ApplePlatform.macos,
          );
          expect(
            exception.toString(),
            '''
Could not find an Xcode project in test_project_path.
If your project does not support macos, you can safely remove test_project_path.
Otherwise, to repair macos, run "flutter create . --platforms macos"''',
          );
        });
      });
    });

    group('flavors', () {
      late Directory projectRoot;

      void copyFixturesToProjectRoot({required String schemesPath}) {
        if (!projectRoot.existsSync()) {
          return;
        }

        final fixturesDir = Directory(p.join(fixturesDirectory, 'xcschemes'));
        for (final file in fixturesDir.listSync().whereType<File>()) {
          final destination = File(
            p.join(projectRoot.path, schemesPath, p.basename(file.path)),
          )..createSync(recursive: true);
          file.copySync(destination.path);
        }
      }

      setUp(() {
        projectRoot = Directory.systemTemp.createTempSync();
        when(
          () => shorebirdEnv.getFlutterProjectRoot(),
        ).thenReturn(projectRoot);
      });

      group('copySupplementFilesToSnapshotDirs', () {
        test('copies all files next to snapshots', () {
          final names = [
            'App.class_table.json',
            'App.dispatch_table.json',
            'App.field_table.json',
            'App.ct.link',
            'App.dt.link',
            'App.ft.link',
            'App.dd.link',
            'App.dd_callers.link',
          ];

          void createFiles(Directory dir) {
            for (final name in names) {
              File(p.join(dir.path, name)).createSync();
            }
          }

          final releaseSupplementDir = Directory.systemTemp.createTempSync();
          final patchSupplementDir = Directory.systemTemp.createTempSync();
          createFiles(releaseSupplementDir);
          createFiles(patchSupplementDir);

          final releaseSnapshotDir = Directory.systemTemp.createTempSync();
          final patchSnapshotDir = Directory.systemTemp.createTempSync();
          runWithOverrides(
            () => apple.copySupplementFilesToSnapshotDirs(
              releaseSupplementDir: releaseSupplementDir,
              releaseSnapshotDir: releaseSnapshotDir,
              patchSupplementDir: patchSupplementDir,
              patchSnapshotDir: patchSnapshotDir,
            ),
          );
          expect(Directory(releaseSnapshotDir.path).listSync(), hasLength(8));
          expect(Directory(patchSnapshotDir.path).listSync(), hasLength(8));
        });

        test('copies only some files next to snapshots', () {
          final names = ['App.class_table.json', 'App.ct.link', 'ignored.txt'];

          void createFiles(Directory dir) {
            for (final name in names) {
              File(p.join(dir.path, name)).createSync();
            }
          }

          final releaseSupplementDir = Directory.systemTemp.createTempSync();
          final patchSupplementDir = Directory.systemTemp.createTempSync();
          createFiles(releaseSupplementDir);
          createFiles(patchSupplementDir);

          final releaseSnapshotDir = Directory.systemTemp.createTempSync();
          final patchSnapshotDir = Directory.systemTemp.createTempSync();
          runWithOverrides(
            () => apple.copySupplementFilesToSnapshotDirs(
              releaseSupplementDir: releaseSupplementDir,
              releaseSnapshotDir: releaseSnapshotDir,
              patchSupplementDir: patchSupplementDir,
              patchSnapshotDir: patchSnapshotDir,
            ),
          );
          expect(Directory(releaseSnapshotDir.path).listSync(), hasLength(2));
          expect(Directory(patchSnapshotDir.path).listSync(), hasLength(2));

          // Logs when copying files.
          final classTableFilePath = p.join(
            releaseSupplementDir.path,
            'App.class_table.json',
          );
          verify(
            () => logger.detail(
              '''Copying supplement file $classTableFilePath to ${releaseSnapshotDir.path}''',
            ),
          ).called(1);
          // Logs about missing files
          final dispatchTableFilePath = p.join(
            releaseSupplementDir.path,
            'App.dispatch_table.json',
          );
          verify(
            () => logger.detail(
              'Unable to find supplement file at $dispatchTableFilePath',
            ),
          ).called(1);
        });
      });

      group('ios', () {
        final schemesPath = p.join(
          'ios',
          'Runner.xcodeproj',
          'xcshareddata',
          'xcschemes',
        );

        setUp(() {
          copyFixturesToProjectRoot(schemesPath: schemesPath);
        });

        group('when ios directory does not exist', () {
          setUp(() {
            Directory(
              p.join(projectRoot.path, 'ios'),
            ).deleteSync(recursive: true);
          });

          test('returns null', () {
            expect(
              runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.ios),
              ),
              isNull,
            );
          });
        });

        group('when xcodeproj does not exist', () {
          setUp(() {
            Directory(
              p.join(projectRoot.path, 'ios', 'Runner.xcodeproj'),
            ).deleteSync(recursive: true);
          });

          test('throws exception', () {
            expect(
              () => runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.ios),
              ),
              throwsA(isA<MissingXcodeProjectException>()),
            );
          });
        });

        group('when xcschemes directory does not exist', () {
          setUp(() {
            Directory(
              p.join(
                projectRoot.path,
                'ios',
                'Runner.xcodeproj',
                'xcshareddata',
              ),
            ).deleteSync(recursive: true);
          });

          test('throws exception', () {
            expect(
              () => runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.ios),
              ),
              throwsException,
            );
          });
        });

        group('when only Runner scheme exists', () {
          setUp(() {
            final schemesDir = Directory(p.join(projectRoot.path, schemesPath));
            for (final schemeFile in schemesDir.listSync().whereType<File>()) {
              if (p.basenameWithoutExtension(schemeFile.path) != 'Runner') {
                schemeFile.deleteSync();
              }
            }
          });

          test('returns no flavors', () {
            expect(
              runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.ios),
              ),
              isEmpty,
            );
          });
        });

        group('when extension and non-extension schemes exist', () {
          test('returns only non-extension schemes', () {
            expect(
              runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.ios),
              ),
              {'internal', 'beta', 'stable', 'dev'},
            );
          });
        });

        group('when a scheme is only in xcuserdata', () {
          setUp(() {
            File(
                p.join(
                  projectRoot.path,
                  'ios',
                  'Runner.xcodeproj',
                  'xcuserdata',
                  'dev.xcuserdatad',
                  'xcschemes',
                  'qa.xcscheme',
                ),
              )
              ..createSync(recursive: true)
              ..writeAsStringSync('<Scheme></Scheme>');
          });

          test('ignores it by default', () {
            expect(
              runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.ios),
              ),
              isNot(contains('qa')),
            );
          });

          test('includes it with includeUserSchemes', () {
            expect(
              runWithOverrides(
                () => apple.flavors(
                  platform: ApplePlatform.ios,
                  includeUserSchemes: true,
                ),
              ),
              {'internal', 'beta', 'stable', 'dev', 'qa'},
            );
          });
        });

        group('when Runner has been renamed', () {
          setUp(() {
            Directory(
              p.join(projectRoot.path, 'ios', 'Runner.xcodeproj'),
            ).renameSync(
              p.join(projectRoot.path, 'ios', 'RenamedRunner.xcodeproj'),
            );
          });

          test('returns only non-extension schemes', () {
            expect(
              runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.ios),
              ),
              {'internal', 'beta', 'stable', 'dev'},
            );
          });
        });
      });

      group('macos', () {
        final schemesPath = p.join(
          'macos',
          'Runner.xcodeproj',
          'xcshareddata',
          'xcschemes',
        );

        setUp(() {
          copyFixturesToProjectRoot(schemesPath: schemesPath);
        });

        group('when macOS directory does not exist', () {
          setUp(() {
            Directory(
              p.join(projectRoot.path, 'macos'),
            ).deleteSync(recursive: true);
          });

          test('returns null', () {
            expect(
              runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.macos),
              ),
              isNull,
            );
          });
        });

        group('when Xcode project does not exist', () {
          setUp(() {
            Directory(
              p.join(projectRoot.path, 'macos', 'Runner.xcodeproj'),
            ).deleteSync(recursive: true);
          });

          test('throws MissingXcodeProjectException', () {
            expect(
              () => runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.macos),
              ),
              throwsA(isA<MissingXcodeProjectException>()),
            );
          });
        });

        group('when schemes directory does not exist', () {
          setUp(() {
            Directory(
              p.join(
                projectRoot.path,
                'macos',
                'Runner.xcodeproj',
                'xcshareddata',
              ),
            ).deleteSync(recursive: true);
          });

          test('throws Exception', () {
            expect(
              () => runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.macos),
              ),
              throwsException,
            );
          });
        });

        group('when schemes are found', () {
          test('returns all schemes except Runner', () {
            expect(
              runWithOverrides(
                () => apple.flavors(platform: ApplePlatform.macos),
              ),
              {'internal', 'beta', 'stable', 'dev'},
            );
          });
        });
      });
    });

    group('runLinker', () {
      const linkPercentage = 42.0;

      late Directory buildDirectory;
      late File aotOutputFile;
      late File analyzeSnapshotFile;
      late File genSnapshotFile;

      setUp(() {
        buildDirectory = Directory.systemTemp.createTempSync();
        aotOutputFile = File(p.join(buildDirectory.path, 'out.aot'))
          ..createSync();
        analyzeSnapshotFile = File(
          p.join(buildDirectory.path, 'analyze_snapshot'),
        )..createSync();
        genSnapshotFile = File(p.join(buildDirectory.path, 'gen_snapshot'))
          ..createSync();

        when(
          () => shorebirdArtifacts.getArtifactPath(
            artifact: ShorebirdArtifact.analyzeSnapshotIos,
          ),
        ).thenReturn(analyzeSnapshotFile.path);
        when(
          () => shorebirdArtifacts.getArtifactPath(
            artifact: ShorebirdArtifact.genSnapshotIos,
          ),
        ).thenReturn(genSnapshotFile.path);

        when(() => shorebirdEnv.buildDirectory).thenReturn(buildDirectory);

        when(
          () => aotTools.link(
            base: any(named: 'base'),
            patch: any(named: 'patch'),
            analyzeSnapshot: any(named: 'analyzeSnapshot'),
            genSnapshot: any(named: 'genSnapshot'),
            kernel: any(named: 'kernel'),
            outputPath: any(named: 'outputPath'),
            workingDirectory: any(named: 'workingDirectory'),
            additionalArgs: any(named: 'additionalArgs'),
            dumpDebugInfoPath: any(named: 'dumpDebugInfoPath'),
          ),
        ).thenAnswer((_) async => linkPercentage);
        when(
          () => aotTools.isLinkDebugInfoSupported(),
        ).thenAnswer((_) async => false);
        when(
          () => aotTools.isLinkMetadataSupported(),
        ).thenAnswer((_) async => true);
      });

      group('when aot snapshot does not exist', () {
        test('logs error and exits with code 70', () async {
          final result = await runWithOverrides(
            () => apple.runLinker(
              aotOutputFile: File('missing'),
              kernelFile: File('missing'),
              releaseArtifact: File('missing'),
              vmCodeFile: File('missing'),
              splitDebugInfoArgs: [],
            ),
          );
          expect(result.exitCode, equals(ExitCode.software.code));
          expect(result.linkPercentage, isNull);

          verify(
            () => logger.err(
              any(that: startsWith('Unable to find patch AOT file at')),
            ),
          ).called(1);
        });
      });

      group('when analyzeSnapshot binary does not exist', () {
        setUp(() {
          when(
            () => shorebirdArtifacts.getArtifactPath(
              artifact: ShorebirdArtifact.analyzeSnapshotIos,
            ),
          ).thenReturn('');
        });

        test('logs error and exits with code 70', () async {
          final result = await runWithOverrides(
            () => apple.runLinker(
              aotOutputFile: aotOutputFile,
              kernelFile: File('missing'),
              releaseArtifact: File('missing'),
              vmCodeFile: File('missing'),
              splitDebugInfoArgs: [],
            ),
          );
          expect(result.exitCode, equals(ExitCode.software.code));
          expect(result.linkPercentage, isNull);

          verify(
            () => logger.err(
              'Unable to find analyze_snapshot at ${File('').path}',
            ),
          ).called(1);
        });
      });

      group('when --split-debug-info is provided', () {
        final tempDirectory = Directory.systemTemp.createTempSync();
        final splitDebugInfoPath = p.join(tempDirectory.path, 'symbols');
        final splitDebugInfoFile = File(
          p.join(splitDebugInfoPath, 'app.ios-arm64.symbols'),
        );
        final splitDebugInfoArgs = [
          '--dwarf-stack-traces',
          '--resolve-dwarf-paths',
          '--save-debugging-info=${splitDebugInfoFile.path}',
        ];

        test('forwards correct args to linker', () async {
          try {
            await runWithOverrides(
              () => apple.runLinker(
                aotOutputFile: aotOutputFile,
                kernelFile: File('missing'),
                releaseArtifact: File('missing'),
                vmCodeFile: File('missing'),
                splitDebugInfoArgs: splitDebugInfoArgs,
              ),
            );
          } on Exception {
            // ignore
          }
          verify(
            () => aotTools.link(
              base: any(named: 'base'),
              patch: any(named: 'patch'),
              analyzeSnapshot: analyzeSnapshotFile.path,
              genSnapshot: genSnapshotFile.path,
              kernel: any(named: 'kernel'),
              outputPath: any(named: 'outputPath'),
              workingDirectory: any(named: 'workingDirectory'),
              dumpDebugInfoPath: any(named: 'dumpDebugInfoPath'),
              additionalArgs: splitDebugInfoArgs,
            ),
          ).called(1);
        });
      });

      group('when isLinkDebugInfoSupported is true', () {
        setUp(() {
          when(aotTools.isLinkDebugInfoSupported).thenAnswer((_) async => true);
        });

        /// Runs the linker against [releaseArtifact] and returns the names of
        /// the snapshots dumped into the debug info directory.
        ///
        /// runLinker deletes that directory before returning, so it is listed
        /// while link metadata is read from it.
        Future<Set<String>> linkAndListDumpedSnapshots(
          File releaseArtifact,
        ) async {
          Set<String>? snapshotFiles;
          when(
            () => aotTools.getLinkMetadata(
              debugDir: any(named: 'debugDir'),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenAnswer((invocation) async {
            final debugDir = invocation.namedArguments[#debugDir] as String;
            snapshotFiles = Directory(p.join(debugDir, 'snapshots'))
                .listSync()
                .whereType<File>()
                .map((f) => p.basename(f.path))
                .toSet();
            return {};
          });

          await runWithOverrides(
            () => apple.runLinker(
              aotOutputFile: aotOutputFile,
              kernelFile: File('missing'),
              releaseArtifact: releaseArtifact,
              vmCodeFile: File('missing'),
              splitDebugInfoArgs: [],
            ),
          );

          expect(snapshotFiles, isNotNull);
          return snapshotFiles!;
        }

        test('deletes the debug info directory and its zip', () async {
          final tempRoot = Directory.systemTemp.createTempSync();
          addTearDown(() => tempRoot.deleteSync(recursive: true));

          await IOOverrides.runZoned(
            () => runWithOverrides(
              () => apple.runLinker(
                aotOutputFile: aotOutputFile,
                kernelFile: File('missing'),
                releaseArtifact: File('missing'),
                vmCodeFile: File('missing'),
                splitDebugInfoArgs: [],
              ),
            ),
            getSystemTempDirectory: () => tempRoot,
          );

          verify(
            () => aotTools.link(
              base: any(named: 'base'),
              patch: any(named: 'patch'),
              analyzeSnapshot: any(named: 'analyzeSnapshot'),
              genSnapshot: any(named: 'genSnapshot'),
              kernel: any(named: 'kernel'),
              outputPath: any(named: 'outputPath'),
              workingDirectory: any(named: 'workingDirectory'),
              dumpDebugInfoPath: any(
                named: 'dumpDebugInfoPath',
                that: startsWith(tempRoot.path),
              ),
            ),
          ).called(1);
          expect(tempRoot.listSync(), isEmpty);
        });

        test('dumps debug info', () async {
          await runWithOverrides(
            () => apple.runLinker(
              aotOutputFile: aotOutputFile,
              kernelFile: File('missing'),
              releaseArtifact: File('missing'),
              vmCodeFile: File('missing'),
              splitDebugInfoArgs: [],
            ),
          );
          verify(
            () => aotTools.link(
              base: any(named: 'base'),
              patch: any(named: 'patch'),
              analyzeSnapshot: any(named: 'analyzeSnapshot'),
              genSnapshot: any(named: 'genSnapshot'),
              kernel: any(named: 'kernel'),
              outputPath: any(named: 'outputPath'),
              workingDirectory: any(named: 'workingDirectory'),
              dumpDebugInfoPath: any(
                named: 'dumpDebugInfoPath',
                that: isNotNull,
              ),
            ),
          ).called(1);
          verify(
            () =>
                logger.detail(any(that: contains('Link debug info saved to'))),
          ).called(1);
        });

        test('copies existing snapshots into debug dump', () async {
          // Create a release artifact in a temp directory.
          final releaseDir = Directory.systemTemp.createTempSync();
          final releaseArtifactFile = File(p.join(releaseDir.path, 'App'))
            ..writeAsStringSync('release');

          // Create intermediate patch snapshots alongside out.aot.
          File(
            p.join(buildDirectory.path, 'out.ct.aot'),
          ).writeAsStringSync('ct');
          File(
            p.join(buildDirectory.path, 'out.preDdOptimized.aot'),
          ).writeAsStringSync('preDdOptimized');
          File(
            p.join(buildDirectory.path, 'out.optimized.aot'),
          ).writeAsStringSync('optimized');

          final snapshotFiles = await linkAndListDumpedSnapshots(
            releaseArtifactFile,
          );
          expect(
            snapshotFiles,
            containsAll(<String>[
              'App',
              'out.aot',
              'out.ct.aot',
              'out.preDdOptimized.aot',
              'out.optimized.aot',
            ]),
          );
        });

        test('skips missing intermediate snapshots', () async {
          // Release artifact exists but intermediate snapshots do not.
          final releaseDir = Directory.systemTemp.createTempSync();
          final releaseArtifactFile = File(p.join(releaseDir.path, 'App'))
            ..writeAsStringSync('release');

          final snapshotFiles = await linkAndListDumpedSnapshots(
            releaseArtifactFile,
          );
          // Only release + patch should be present (no ct/optimized).
          expect(snapshotFiles, equals(<String>{'App', 'out.aot'}));
        });

        group('when running in codemagic', () {
          late Directory codemagicExportDir;

          setUp(() {
            codemagicExportDir = Directory.systemTemp.createTempSync();
            platform = platform.copyWith(
              environment: {'CM_EXPORT_DIR': codemagicExportDir.path},
            );
          });

          test('copies debug info to codemagic exports', () async {
            final copiedPatchDebugInfo = File(
              p.join(codemagicExportDir.path, 'patch-debug.zip'),
            );
            expect(copiedPatchDebugInfo.existsSync(), isFalse);
            await runWithOverrides(
              () => apple.runLinker(
                aotOutputFile: aotOutputFile,
                kernelFile: File('missing'),
                releaseArtifact: File('missing'),
                vmCodeFile: File('missing'),
                splitDebugInfoArgs: [],
              ),
            );
            expect(copiedPatchDebugInfo.existsSync(), isTrue);
            verify(
              () => logger.detail(
                any(that: startsWith('Codemagic environment detected.')),
              ),
            ).called(1);
          });

          test('gracefully handles errors', () async {
            platform = platform.copyWith(
              environment: {'CM_EXPORT_DIR': 'invalid path'},
            );
            await runWithOverrides(
              () => apple.runLinker(
                aotOutputFile: aotOutputFile,
                kernelFile: File('missing'),
                releaseArtifact: File('missing'),
                vmCodeFile: File('missing'),
                splitDebugInfoArgs: [],
              ),
            );

            verify(
              () => logger.detail(
                any(
                  that: contains('PathNotFoundException: Cannot copy file to'),
                ),
              ),
            ).called(1);
          });
        });
      });

      group('when call to aotTools.link fails', () {
        setUp(() {
          when(
            () => aotTools.link(
              base: any(named: 'base'),
              patch: any(named: 'patch'),
              analyzeSnapshot: any(named: 'analyzeSnapshot'),
              genSnapshot: any(named: 'genSnapshot'),
              kernel: any(named: 'kernel'),
              outputPath: any(named: 'outputPath'),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenThrow(Exception('oops'));
        });

        test('logs error and exits with code 70', () async {
          await runWithOverrides(
            () => apple.runLinker(
              aotOutputFile: aotOutputFile,
              kernelFile: File('missing'),
              releaseArtifact: File('missing'),
              vmCodeFile: File('missing'),
              splitDebugInfoArgs: [],
            ),
          );

          verify(
            () => progress.fail('Failed to link AOT files: Exception: oops'),
          ).called(1);
        });
      });

      group('when call to aotTools.link succeeds', () {
        test('completes and exits with code 0', () async {
          final result = await runWithOverrides(
            () => apple.runLinker(
              aotOutputFile: aotOutputFile,
              kernelFile: File('missing'),
              releaseArtifact: File('missing'),
              vmCodeFile: File('missing'),
              splitDebugInfoArgs: [],
            ),
          );
          expect(result.exitCode, equals(ExitCode.success.code));
          expect(result.linkPercentage, equals(linkPercentage));
        });
      });

      group('when call to aotTools.getLinkMetadata fails', () {
        setUp(() {
          when(
            () => aotTools.isLinkDebugInfoSupported(),
          ).thenAnswer((_) async => true);
          when(
            () => aotTools.getLinkMetadata(
              debugDir: any(named: 'debugDir'),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).thenThrow(Exception('oops'));
        });

        test('warns and records the reason as the link metadata', () async {
          final result = await runWithOverrides(
            () => apple.runLinker(
              aotOutputFile: aotOutputFile,
              kernelFile: File('missing'),
              releaseArtifact: File('missing'),
              vmCodeFile: File('missing'),
              splitDebugInfoArgs: [],
            ),
          );

          verify(
            () => logger.detail(
              '[aot_tools] Failed to get link metadata: Exception: oops',
            ),
          ).called(1);
          verify(
            () => logger.warn(
              'Could not read link details for this patch (Exception: oops). '
              'The patch is not affected; the reason is sent to Shorebird '
              'with the patch so it can be fixed.',
            ),
          ).called(1);
          verify(() => progress.complete()).called(1);
          expect(result.exitCode, equals(0));
          expect(result.linkMetadata, equals({'error': 'Exception: oops'}));
        });
      });

      group('when aot_tools has no link_metadata command', () {
        setUp(() {
          when(
            () => aotTools.isLinkDebugInfoSupported(),
          ).thenAnswer((_) async => true);
          when(
            () => aotTools.isLinkMetadataSupported(),
          ).thenAnswer((_) async => false);
        });

        test('records no link metadata and does not warn', () async {
          final result = await runWithOverrides(
            () => apple.runLinker(
              aotOutputFile: aotOutputFile,
              kernelFile: File('missing'),
              releaseArtifact: File('missing'),
              vmCodeFile: File('missing'),
              splitDebugInfoArgs: [],
            ),
          );

          verify(() => aotTools.isLinkMetadataSupported()).called(1);
          verifyNever(
            () => aotTools.getLinkMetadata(
              debugDir: any(named: 'debugDir'),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          );
          verifyNever(() => logger.warn(any()));
          verify(() => progress.complete()).called(1);
          expect(result.exitCode, equals(0));
          expect(result.linkMetadata, isNull);
        });
      });
    });
  });

  group(linkMetadataFailureReason, () {
    test('names the exception aot_tools left unhandled', () {
      const error = AotToolsExecutionFailure(
        exitCode: 255,
        stdout: '',
        stderr: '''
Unhandled exception:
Bad state: A node should not be linked if it makes a direct call into an unlinked node.
#0      accumulateUnlinkedCallers (package:aot_tools/src/linker/link_stats.dart:235)
''',
        command: 'aot_tools link_metadata /tmp/debug',
      );
      expect(
        linkMetadataFailureReason(error),
        equals(
          'Bad state: A node should not be linked if it makes a direct call '
          'into an unlinked node.',
        ),
      );
    });

    test('replaces paths', () {
      const error = AotToolsExecutionFailure(
        exitCode: 1,
        stdout: '',
        stderr: 'PathNotFound: /Users/someone/Acme App/build/App.dt.link\n',
        command: 'aot_tools link_metadata /tmp/debug',
      );
      expect(
        linkMetadataFailureReason(error),
        equals('PathNotFound: <path>'),
      );
    });

    test('replaces a Windows path that starts near the length limit', () {
      final error = AotToolsExecutionFailure(
        exitCode: 1,
        stdout: '',
        stderr: 'Error: ${'x' * 190} C:\\Users\\someone\\app',
        command: 'aot_tools link_metadata /tmp/debug',
      );
      expect(
        linkMetadataFailureReason(error),
        equals('Error: ${'x' * 190} <path>'),
      );
    });

    test('falls back to the exit code when stderr is empty', () {
      const error = AotToolsExecutionFailure(
        exitCode: 3,
        stdout: '',
        stderr: '',
        command: 'aot_tools link_metadata /tmp/debug',
      );
      expect(linkMetadataFailureReason(error), equals('exit code 3'));
    });

    test('quotes the start of output that is not JSON', () {
      const error = FormatException(
        'Unexpected character',
        'Running build hooks...Running build hooks...{"a":1,"b":2,"c":3,"d":4}',
      );
      expect(
        linkMetadataFailureReason(error),
        equals(
          'invalid JSON: '
          '"Running build hooks...Running build hooks...{"a":1,"b":2,"c""',
        ),
      );
    });

    test('says invalid JSON when the output is unknown', () {
      expect(
        linkMetadataFailureReason(const FormatException('bad')),
        equals('invalid JSON'),
      );
    });
  });
}

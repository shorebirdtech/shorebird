import 'dart:io' hide Platform;

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(InvalidExportOptionsPlistException, () {
    test('toString', () {
      final exception = InvalidExportOptionsPlistException('message');
      expect(exception.toString(), 'message');
    });
  });

  group(Apple, () {
    late AotTools aotTools;
    late Apple apple;
    late Progress progress;
    late Platform platform;
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
      platform = MockPlatform();
      progress = MockProgress();
      logger = MockShorebirdLogger();
      shorebirdArtifacts = MockShorebirdArtifacts();
      shorebirdEnv = MockShorebirdEnv();

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => platform.environment).thenReturn({});

      when(
        () => aotTools.getLinkMetadata(
          debugDir: any(named: 'debugDir'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => {'key': 'value'});
    });

    group(MissingXcodeProjectException, () {
      test('toString', () {
        const exception = MissingXcodeProjectException('test_project_path');
        expect(exception.toString(), '''
Could not find an Xcode project in test_project_path.
To add iOS, run "flutter create . --platforms ios"
To add macOS, run "flutter create . --platforms macos"''');
      });
    });

    group('flavors', () {
      late Directory projectRoot;

      void copyFixturesToProjectRoot({required String schemesPath}) {
        if (!projectRoot.existsSync()) {
          return;
        }

        final fixturesDir = Directory(p.join('test', 'fixtures', 'xcschemes'));
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
          apple.copySupplementFilesToSnapshotDirs(
            releaseSupplementDir: releaseSupplementDir,
            releaseSnapshotDir: releaseSnapshotDir,
            patchSupplementDir: patchSupplementDir,
            patchSnapshotDir: patchSnapshotDir,
          );
          expect(Directory(releaseSnapshotDir.path).listSync(), hasLength(6));
          expect(Directory(patchSnapshotDir.path).listSync(), hasLength(6));
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
          apple.copySupplementFilesToSnapshotDirs(
            releaseSupplementDir: releaseSupplementDir,
            releaseSnapshotDir: releaseSnapshotDir,
            patchSupplementDir: patchSupplementDir,
            patchSnapshotDir: patchSnapshotDir,
          );
          expect(Directory(releaseSnapshotDir.path).listSync(), hasLength(2));
          expect(Directory(patchSnapshotDir.path).listSync(), hasLength(2));
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
            () => logger.err('Unable to find analyze_snapshot at '),
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

        group('when running in codemagic', () {
          late Directory codemagicExportDir;

          setUp(() {
            codemagicExportDir = Directory.systemTemp.createTempSync();
            when(
              () => platform.environment,
            ).thenReturn({'CM_EXPORT_DIR': codemagicExportDir.path});
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
            when(
              () => platform.environment,
            ).thenReturn({'CM_EXPORT_DIR': 'invalid path'});
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
            () => logger.detail(
              '[aot_tools] Failed to get link metadata: Exception: oops',
            ),
          ).called(1);
          verify(() => progress.complete()).called(1);
        });
      });
    });
  });
}

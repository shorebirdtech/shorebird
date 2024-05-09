import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/executables/aot_tools.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_linker.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(ShorebirdLinker, () {
    const postLinkerFlutterRevision =
        'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
    const preLinkerFlutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';

    late AotTools aotTools;
    late ArtifactManager artifactManager;
    late EngineConfig engineConfig;
    late File analyzeSnapshotFile;
    late File genSnapshotFile;
    late Directory flutterDirectory;
    late Directory projectRoot;
    late ShorebirdArtifacts shorebirdArtifacts;
    late ShorebirdEnv shorebirdEnv;

    late ShorebirdLinker shorebirdLinker;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          aotToolsRef.overrideWith(() => aotTools),
          artifactManagerRef.overrideWith(() => artifactManager),
          engineConfigRef.overrideWith(() => engineConfig),
          shorebirdArtifactsRef.overrideWith(() => shorebirdArtifacts),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(File(''));
    });

    setUp(() {
      aotTools = MockAotTools();
      artifactManager = MockArtifactManager();
      engineConfig = MockEngineConfig();
      shorebirdArtifacts = MockShorebirdArtifacts();
      shorebirdEnv = MockShorebirdEnv();

      projectRoot = Directory.systemTemp.createTempSync();
      final shorebirdRoot = Directory.systemTemp.createTempSync();
      flutterDirectory = Directory(
        p.join(shorebirdRoot.path, 'bin', 'cache', 'flutter'),
      );
      File(p.join(projectRoot.path, 'build', 'out.aot')).createSync(
        recursive: true,
      );
      genSnapshotFile = File(
        p.join(
          flutterDirectory.path,
          'bin',
          'cache',
          'artifacts',
          'engine',
          'ios-release',
          'gen_snapshot_arm64',
        ),
      )..createSync(recursive: true);
      analyzeSnapshotFile = File(
        p.join(
          flutterDirectory.path,
          'bin',
          'cache',
          'artifacts',
          'engine',
          'ios-release',
          'analyze_snapshot_arm64',
        ),
      )..createSync(recursive: true);

      when(() => artifactManager.newestAppDill()).thenReturn(File(''));

      when(() => engineConfig.localEngine).thenReturn(null);

      when(
        () => shorebirdArtifacts.getArtifactPath(
          artifact: ShorebirdArtifact.analyzeSnapshot,
        ),
      ).thenReturn(analyzeSnapshotFile.path);
      when(
        () => shorebirdArtifacts.getArtifactPath(
          artifact: ShorebirdArtifact.genSnapshot,
        ),
      ).thenReturn(genSnapshotFile.path);
      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);

      shorebirdLinker = ShorebirdLinker();
    });

    group('linkPatchArtifactIfPossible', () {
      group('when the linker is not used', () {
        setUp(() {
          when(() => shorebirdEnv.flutterRevision)
              .thenReturn(preLinkerFlutterRevision);
        });

        group('when generating a patch diff is supported', () {
          setUp(() {
            when(() => aotTools.isGeneratePatchDiffBaseSupported())
                .thenAnswer((_) async => true);
          });
        });

        group('when generating a patch diff is not supported', () {
          setUp(() {
            when(() => aotTools.isGeneratePatchDiffBaseSupported())
                .thenAnswer((_) async => false);
          });

          test('returns the patch build file', () async {
            final releaseArtifact = File('release_artifact');
            final patchBuildFile = File('patch_build_file');

            final result = await runWithOverrides(
              () => shorebirdLinker.linkPatchArtifactIfPossible(
                releaseArtifact: releaseArtifact,
                patchSnapshotFile: patchBuildFile,
              ),
            );

            expect(result.patchBuildFile, equals(patchBuildFile));
            expect(result.linkPercentage, isNull);

            verifyNever(
              () => aotTools.link(
                base: any(named: 'base'),
                patch: any(named: 'patch'),
                analyzeSnapshot: any(named: 'analyzeSnapshot'),
                genSnapshot: any(named: 'genSnapshot'),
                kernel: any(named: 'kernel'),
                outputPath: any(named: 'outputPath'),
                workingDirectory: any(named: 'workingDirectory'),
              ),
            );
          });
        });
      });

      group('when linker is used', () {
        const linkPercentage = 0.5;
        group('when no diff is generated', () {
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
            ).thenAnswer((_) async => linkPercentage);
            when(() => aotTools.isGeneratePatchDiffBaseSupported())
                .thenAnswer((_) async => false);
            when(() => shorebirdEnv.flutterRevision)
                .thenReturn(postLinkerFlutterRevision);
          });

          test('returns the linked patch build file', () async {
            final releaseArtifact = File('release_artifact');
            final patchBuildFile = File('patch_build_file');

            final result = await runWithOverrides(
              () => shorebirdLinker.linkPatchArtifactIfPossible(
                releaseArtifact: releaseArtifact,
                patchSnapshotFile: patchBuildFile,
              ),
            );

            expect(result.patchBuildFile, isA<File>());
            expect(result.linkPercentage, equals(linkPercentage));
            verifyNever(
              () => artifactManager.createDiff(
                releaseArtifactPath: any(named: 'releaseArtifactPath'),
                patchArtifactPath: any(named: 'patchArtifactPath'),
              ),
            );
          });

          group('when linking fails', () {
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

            test('throws a LinkFailureException', () async {
              final releaseArtifact = File('release_artifact');
              final patchBuildFile = File('patch_build_file');

              expect(
                () => runWithOverrides(
                  () => shorebirdLinker.linkPatchArtifactIfPossible(
                    releaseArtifact: releaseArtifact,
                    patchSnapshotFile: patchBuildFile,
                  ),
                ),
                throwsA(
                  isA<LinkFailureException>().having(
                    (e) => e.toString(),
                    'toString',
                    '''LinkFailureException: Exception: oops''',
                  ),
                ),
              );
            });
          });
        });

        group('when a diff is generated', () {
          const linkPercentage = 0.75;

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
            ).thenAnswer((_) async => linkPercentage);
            when(() => aotTools.isGeneratePatchDiffBaseSupported())
                .thenAnswer((_) async => true);
            when(
              () => aotTools.generatePatchDiffBase(
                analyzeSnapshotPath: any(named: 'analyzeSnapshotPath'),
                releaseSnapshot: any(named: 'releaseSnapshot'),
              ),
            ).thenAnswer((_) async => File('patch_base_file'));
            when(
              () => artifactManager.createDiff(
                releaseArtifactPath: any(named: 'releaseArtifactPath'),
                patchArtifactPath: any(named: 'patchArtifactPath'),
              ),
            ).thenAnswer((_) async => 'diff.patch');
            when(() => shorebirdEnv.flutterRevision)
                .thenReturn(postLinkerFlutterRevision);
          });

          test('returns the linked patch build file', () async {
            final releaseArtifact = File('release_artifact');
            final patchBuildFile = File('patch_build_file');

            final result = await runWithOverrides(
              () => shorebirdLinker.linkPatchArtifactIfPossible(
                releaseArtifact: releaseArtifact,
                patchSnapshotFile: patchBuildFile,
              ),
            );

            expect(result.patchBuildFile, isA<File>());
            expect(result.patchBuildFile.path, equals('diff.patch'));
            expect(result.linkPercentage, equals(linkPercentage));
            verify(
              () => artifactManager.createDiff(
                releaseArtifactPath: any(named: 'releaseArtifactPath'),
                patchArtifactPath: any(named: 'patchArtifactPath'),
              ),
            ).called(1);
          });
        });
      });
    });
  });
}

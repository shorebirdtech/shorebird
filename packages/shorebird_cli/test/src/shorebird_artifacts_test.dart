import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(ShorebirdCachedArtifacts, () {
    const engineRevision = 'engine-revision';
    late Cache cache;
    late Directory flutterDirectory;
    late Directory artifactDirectory;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdCachedArtifacts artifacts;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          cacheRef.overrideWith(() => cache),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      cache = MockCache();
      final tmpDir = Directory.systemTemp.createTempSync();
      flutterDirectory = Directory(p.join(tmpDir.path, 'flutter'))
        ..createSync(recursive: true);
      artifactDirectory = Directory(p.join(tmpDir.path, 'artifacts'))
        ..createSync(recursive: true);
      shorebirdEnv = MockShorebirdEnv();
      artifacts = const ShorebirdCachedArtifacts();

      when(
        () => cache.getArtifactDirectory(any()),
      ).thenReturn(artifactDirectory);
      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(() => shorebirdEnv.shorebirdEngineRevision)
          .thenReturn(engineRevision);
    });

    group('getArtifactPath', () {
      group('aot-tools', () {
        const aotToolsKernel = 'aot-tools.dill';
        const aotToolsExe = 'aot-tools';
        late String aotToolsKernelPath;
        late String aotToolsExePath;

        setUp(() {
          aotToolsKernelPath = p.join(
            artifactDirectory.path,
            engineRevision,
            aotToolsKernel,
          );
          aotToolsExePath = p.join(
            artifactDirectory.path,
            engineRevision,
            aotToolsExe,
          );
        });

        group('when kernel and executable are present', () {
          setUp(() {
            File(aotToolsKernelPath).createSync(recursive: true);
            File(aotToolsExePath).createSync(recursive: true);
          });

          test('returns path to kernel file', () async {
            expect(
              runWithOverrides(
                () => artifacts.getArtifactPath(
                  artifact: ShorebirdArtifact.aotTools,
                ),
              ),
              equals(aotToolsKernelPath),
            );
          });
        });

        group('when only executable is present', () {
          setUp(() {
            File(aotToolsExePath).createSync(recursive: true);
          });

          test('returns path to executable file', () {
            expect(
              runWithOverrides(
                () => artifacts.getArtifactPath(
                  artifact: ShorebirdArtifact.aotTools,
                ),
              ),
              equals(aotToolsExePath),
            );
          });
        });
      });

      group('gen_snapshot', () {
        test('returns correct path', () {
          expect(
            runWithOverrides(
              () => artifacts.getArtifactPath(
                artifact: ShorebirdArtifact.genSnapshot,
              ),
            ),
            equals(
              p.join(
                flutterDirectory.path,
                'bin',
                'cache',
                'artifacts',
                'engine',
                'ios-release',
                'gen_snapshot_arm64',
              ),
            ),
          );
        });
      });

      group('analyze_snapshot', () {
        test('returns correct path', () {
          expect(
            runWithOverrides(
              () => artifacts.getArtifactPath(
                artifact: ShorebirdArtifact.analyzeSnapshot,
              ),
            ),
            equals(
              p.join(
                flutterDirectory.path,
                'bin',
                'cache',
                'artifacts',
                'engine',
                'ios-release',
                'analyze_snapshot_arm64',
              ),
            ),
          );
        });
      });

      group('updater_tools', () {
        test('returns correct path', () {
          expect(
            runWithOverrides(
              () => artifacts.getArtifactPath(
                artifact: ShorebirdArtifact.updaterTools,
              ),
            ),
            equals(
              p.join(
                artifactDirectory.path,
                engineRevision,
                'updater-tools.dill',
              ),
            ),
          );
        });
      });
    });
  });

  group(ShorebirdLocalEngineArtifacts, () {
    late String localEngineSrcPath;
    late String localEngine;
    late EngineConfig engineConfig;
    late ShorebirdLocalEngineArtifacts artifacts;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          engineConfigRef.overrideWith(() => engineConfig),
        },
      );
    }

    setUp(() {
      localEngineSrcPath = 'local_engine_src_path';
      localEngine = 'local_engine';
      engineConfig = MockEngineConfig();
      artifacts = const ShorebirdLocalEngineArtifacts();

      when(
        () => engineConfig.localEngineSrcPath,
      ).thenReturn(localEngineSrcPath);
      when(
        () => engineConfig.localEngine,
      ).thenReturn(localEngine);
    });

    group('getArtifactPath', () {
      group('aot-tools', () {
        test('returns correct path', () {
          expect(
            runWithOverrides(
              () => artifacts.getArtifactPath(
                artifact: ShorebirdArtifact.aotTools,
              ),
            ),
            equals(
              p.join(
                localEngineSrcPath,
                'third_party',
                'dart',
                'pkg',
                'aot_tools',
                'bin',
                'aot_tools.dart',
              ),
            ),
          );
        });
      });

      group('gen_snapshot', () {
        test('returns correct path', () {
          expect(
            runWithOverrides(
              () => artifacts.getArtifactPath(
                artifact: ShorebirdArtifact.genSnapshot,
              ),
            ),
            equals(
              p.join(
                localEngineSrcPath,
                'out',
                localEngine,
                'clang_x64',
                'gen_snapshot_arm64',
              ),
            ),
          );
        });
      });

      group('analyze_snapshot', () {
        test('returns correct path', () {
          expect(
            runWithOverrides(
              () => artifacts.getArtifactPath(
                artifact: ShorebirdArtifact.analyzeSnapshot,
              ),
            ),
            equals(
              p.join(
                localEngineSrcPath,
                'out',
                localEngine,
                'clang_x64',
                'analyze_snapshot_arm64',
              ),
            ),
          );
        });

        group('updater-tools', () {
          test('returns correct path', () {
            expect(
              runWithOverrides(
                () => artifacts.getArtifactPath(
                  artifact: ShorebirdArtifact.updaterTools,
                ),
              ),
              equals(
                p.join(
                  localEngineSrcPath,
                  'third_party',
                  'updater',
                  'updater_tools',
                  'bin',
                  'updater_tools.dart',
                ),
              ),
            );
          });
        });
      });
    });
  });
}

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

      test('returns correct path for iOS gen_snapshot', () {
        expect(
          runWithOverrides(
            () => artifacts.getArtifactPath(
              artifact: ShorebirdArtifact.genSnapshotIos,
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

      test('returns correct path for macOS gen_snapshot', () {
        expect(
          runWithOverrides(
            () => artifacts.getArtifactPath(
              artifact: ShorebirdArtifact.genSnapshotMacOS,
            ),
          ),
          equals(
            p.join(
              flutterDirectory.path,
              'bin',
              'cache',
              'artifacts',
              'engine',
              'darwin-x64-release',
              'gen_snapshot',
            ),
          ),
        );
      });

      test('returns correct path for analyze_snapshot on iOS', () {
        expect(
          runWithOverrides(
            () => artifacts.getArtifactPath(
              artifact: ShorebirdArtifact.analyzeSnapshotIos,
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

      test('returns correct path for analyze_snapshot on macOS', () {
        expect(
          runWithOverrides(
            () => artifacts.getArtifactPath(
              artifact: ShorebirdArtifact.analyzeSnapshotMacOS,
            ),
          ),
          equals(
            p.join(
              flutterDirectory.path,
              'bin',
              'cache',
              'artifacts',
              'engine',
              'darwin-x64-release',
              'analyze_snapshot',
            ),
          ),
        );
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
      test('returns correct path for aot tools', () {
        expect(
          runWithOverrides(
            () => artifacts.getArtifactPath(
              artifact: ShorebirdArtifact.aotTools,
            ),
          ),
          equals(
            p.join(
              localEngineSrcPath,
              'flutter',
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

      test('returns correct path for gen_snapshot on iOS', () {
        expect(
          runWithOverrides(
            () => artifacts.getArtifactPath(
              artifact: ShorebirdArtifact.genSnapshotIos,
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

      test('returns correct path for gen_snapshot on macOS', () {
        expect(
          runWithOverrides(
            () => artifacts.getArtifactPath(
              artifact: ShorebirdArtifact.genSnapshotMacOS,
            ),
          ),
          equals(
            p.join(
              localEngineSrcPath,
              'out',
              localEngine,
              'clang_x64',
              'gen_snapshot',
            ),
          ),
        );
      });

      test('returns correct path for analyze_snapshot on iOS', () {
        expect(
          runWithOverrides(
            () => artifacts.getArtifactPath(
              artifact: ShorebirdArtifact.analyzeSnapshotIos,
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

      test('returns correct path for analyze_snapshot on macOS', () {
        expect(
          runWithOverrides(
            () => artifacts.getArtifactPath(
              artifact: ShorebirdArtifact.analyzeSnapshotMacOS,
            ),
          ),
          equals(
            p.join(
              localEngineSrcPath,
              'out',
              localEngine,
              'clang_x64',
              'analyze_snapshot',
            ),
          ),
        );
      });
    });
  });
}

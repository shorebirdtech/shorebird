import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/flutter_artifacts.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(FlutterCachedArtifacts, () {
    late Directory flutterDirectory;
    late ShorebirdEnv shorebirdEnv;
    late FlutterCachedArtifacts artifacts;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      flutterDirectory = Directory('flutter');
      shorebirdEnv = MockShorebirdEnv();
      artifacts = const FlutterCachedArtifacts();

      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
    });

    group('getArtifactPath', () {
      test('returns correct path for gen_snapshot', () {
        expect(
          runWithOverrides(
            () => artifacts.getArtifactPath(
              artifact: FlutterArtifact.genSnapshot,
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

      test('returns correct path for analyze_snapshot', () {
        expect(
          runWithOverrides(
            () => artifacts.getArtifactPath(
              artifact: FlutterArtifact.analyzeSnapshot,
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
  });

  group(FlutterLocalEngineArtifacts, () {
    late String localEngineSrcPath;
    late EngineConfig engineConfig;
    late FlutterLocalEngineArtifacts artifacts;

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
      engineConfig = MockEngineConfig();
      artifacts = const FlutterLocalEngineArtifacts();

      when(
        () => engineConfig.localEngineSrcPath,
      ).thenReturn(localEngineSrcPath);
    });

    group('getArtifactPath', () {
      test('returns correct path for gen_snapshot', () {
        expect(
          runWithOverrides(
            () => artifacts.getArtifactPath(
              artifact: FlutterArtifact.genSnapshot,
            ),
          ),
          equals(
            p.join(
              localEngineSrcPath,
              'out',
              'ios_release',
              'clang_x64',
              'gen_snapshot_arm64',
            ),
          ),
        );
      });

      test('returns correct path for analyze_snapshot', () {
        expect(
          runWithOverrides(
            () => artifacts.getArtifactPath(
              artifact: FlutterArtifact.analyzeSnapshot,
            ),
          ),
          equals(
            p.join(
              localEngineSrcPath,
              'out',
              'ios_release',
              'clang_x64',
              'analyze_snapshot_arm64',
            ),
          ),
        );
      });
    });
  });
}

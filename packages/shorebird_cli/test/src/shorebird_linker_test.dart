import 'dart:io';
import 'dart:math';

import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_linker.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(ShorebirdLinker, () {
    const postLinkerFlutterRevision =
        'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
    const preLinkerFlutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';

    late EngineConfig engineConfig;
    late ShorebirdEnv shorebirdEnv;

    late ShorebirdLinker shorebirdLinker;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          engineConfigRef.overrideWith(() => engineConfig),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      engineConfig = MockEngineConfig();
      shorebirdEnv = MockShorebirdEnv();

      shorebirdLinker = ShorebirdLinker();
    });

    group('linkPatchArtifactIfPossible', () {
      group('when the linker is not used', () {
        setUp(() {
          when(() => engineConfig.localEngine).thenReturn(null);
          when(() => shorebirdEnv.flutterRevision)
              .thenReturn(preLinkerFlutterRevision);
        });

        test('returns the patch build file', () async {
          final releaseArtifact = File('release_artifact');
          final patchBuildFile = File('patch_build_file');

          final result = await runWithOverrides(
            () => shorebirdLinker.linkPatchArtifactIfPossible(
              releaseArtifact: releaseArtifact,
              patchBuildFile: patchBuildFile,
            ),
          );

          expect(result.patchBuildFile, patchBuildFile);
          expect(result.linkPercentage, isNull);
        });
      });
    });
  });
}

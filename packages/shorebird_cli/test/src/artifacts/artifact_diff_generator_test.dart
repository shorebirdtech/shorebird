import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifacts/artifacts.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(ArtifactDiffGenerator, () {
    late ShorebirdProcessResult patchProcessResult;
    late ShorebirdProcess shorebirdProcess;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          bundletoolRef.overrideWith(() => bundletool),
          cacheRef.overrideWith(() => cache),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          javaRef.overrideWith(() => java),
          loggerRef.overrideWith(() => logger),
          patchDiffCheckerRef.overrideWith(() => patchDiffChecker),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    Directory setUpTempDir() {
      final tempDir = Directory.systemTemp.createTempSync();
      // File(
      //   p.join(tempDir.path, 'pubspec.yaml'),
      // ).writeAsStringSync(pubspecYamlContent);
      // File(
      //   p.join(tempDir.path, 'shorebird.yaml'),
      // ).writeAsStringSync('app_id: $appId');
      return tempDir;
    }

    void setUpTempArtifacts(Directory dir, {String? flavor}) {
      for (final archMetadata
          in ShorebirdBuildMixin.allAndroidArchitectures.values) {
        final artifactPath = p.join(
          dir.path,
          'build',
          'app',
          'intermediates',
          'stripped_native_libs',
          flavor != null ? '${flavor}Release' : 'release',
          'out',
          'lib',
          archMetadata.path,
          'libapp.so',
        );
        File(artifactPath).createSync(recursive: true);
      }
    }

    setUp(() {
      patchProcessResult = MockProcessResult();
      shorebirdProcess = MockShorebirdProcess();

      when(
        () => shorebirdProcess.run(
          any(that: endsWith('patch')),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((invocation) async {
        final args = invocation.positionalArguments[1] as List<String>;
        final diffPath = args[2];
        File(diffPath)
          ..createSync(recursive: true)
          ..writeAsStringSync('diff');
        return patchProcessResult;
      });
      when(() => patchProcessResult.exitCode).thenReturn(ExitCode.success.code);
    });

    group('', () {
      test('throws error when creating diff fails', () async {
        const error = 'oops something went wrong';
        when(() => patchProcessResult.exitCode).thenReturn(1);
        when(() => patchProcessResult.stderr).thenReturn(error);
        final tempDir = setUpTempDir();
        setUpTempArtifacts(tempDir);
        final exitCode = await IOOverrides.runZoned(
          () => runWithOverrides(command.run),
          getCurrentDirectory: () => tempDir,
        );
        verify(
          () => progress.fail('Exception: Failed to create diff: $error'),
        ).called(1);
        expect(exitCode, ExitCode.software.code);
      });

      /// TODO
    });
  });
}

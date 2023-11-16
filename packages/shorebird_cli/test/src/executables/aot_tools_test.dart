import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('AotTools', () {
    late Cache cache;
    late ShorebirdProcess process;
    late Directory workingDirectory;
    late AotTools aotTools;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          cacheRef.overrideWith(() => cache),
          processRef.overrideWith(() => process),
        },
      );
    }

    setUp(() {
      cache = MockCache();
      process = MockShorebirdProcess();
      workingDirectory = Directory.systemTemp.createTempSync('aot-tool test');
      aotTools = AotTools();

      when(() => cache.updateAll()).thenAnswer((_) async {});
      when(
        () => cache.getArtifactDirectory(any()),
      ).thenReturn(workingDirectory);
    });

    group('link', () {
      const base = './path/to/base.aot';
      const patch = './path/to/patch.aot';
      const analyzeSnapshot = './path/to/analyze_snapshot.aot';

      test('throws Exception when process exits with non-zero code', () async {
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
        await expectLater(
          () => runWithOverrides(
            () => aotTools.link(
              base: base,
              patch: patch,
              analyzeSnapshot: analyzeSnapshot,
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

      test('completes when linking exits with code: 0', () async {
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
              workingDirectory: workingDirectory.path,
            ),
          ),
          completes,
        );
        verify(
          () => process.run(
            any(that: endsWith(AotTools.executableName)),
            [
              'link',
              '--base=$base',
              '--patch=$patch',
              '--analyze-snapshot=$analyzeSnapshot',
            ],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).called(1);
      });
    });
  });
}

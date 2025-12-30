import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/diff.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(Diff, () {
    late ShorebirdProcess process;
    late Diff diff;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(body, values: {processRef.overrideWith(() => process)});
    }

    setUp(() {
      process = MockShorebirdProcess();
      diff = Diff();
    });

    group('run', () {
      setUp(() {
        when(() => process.run(any(), any())).thenAnswer(
          (_) async => const ShorebirdProcessResult(
            exitCode: 0,
            stdout: 'stdout',
            stderr: 'stderr',
          ),
        );
      });

      test('returns the result of the `diff` command', () async {
        await runWithOverrides(
          () => diff.run(
            'fileA',
            'fileB',
            unified: true,
            colorMode: DiffColorMode.always,
          ),
        );
        verify(
          () => process.run(Diff.executable, [
            '--unified',
            '--color=always',
            'fileA',
            'fileB',
          ]),
        ).called(1);
      });
    });
  });
}

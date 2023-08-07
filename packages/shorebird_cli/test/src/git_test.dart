import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/git.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockShorebirdProcessResult extends Mock
    implements ShorebirdProcessResult {}

void main() {
  group(Git, () {
    late ShorebirdProcessResult processResult;
    late ShorebirdProcess process;
    late Git git;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          processRef.overrideWith(() => process),
          gitRef.overrideWith(() => git),
        },
      );
    }

    setUp(() {
      processResult = _MockShorebirdProcessResult();
      process = _MockShorebirdProcess();
      git = runWithOverrides(Git.new);

      when(
        () => process.run(any(), any(), runInShell: any(named: 'runInShell')),
      ).thenAnswer((_) async => processResult);
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
    });

    group('clone', () {
      const url = 'https://github.com/shorebirdtech/shorebird';
      const outputDirectory = './output';

      test('executes correct command (no args)', () async {
        await runWithOverrides(
          () => git.clone(
            url: url,
            outputDirectory: outputDirectory,
          ),
        );
        verify(
          () => process.run(
            'git',
            ['clone', url, outputDirectory],
            runInShell: true,
          ),
        ).called(1);
      });

      test('executes correct command (with args)', () async {
        const args = <String>['--filter-tree:0', '--no-checkout'];
        await runWithOverrides(
          () => git.clone(
            url: url,
            args: ['--filter-tree:0', '--no-checkout'],
            outputDirectory: outputDirectory,
          ),
        );
        verify(
          () => process.run(
            'git',
            ['clone', url, ...args, outputDirectory],
            runInShell: true,
          ),
        ).called(1);
      });

      test('throws ProcessException if process exits with error', () async {
        const error = 'oops';
        when(() => processResult.exitCode).thenReturn(ExitCode.software.code);
        when(() => processResult.stderr).thenReturn(error);
        expect(
          () => runWithOverrides(
            () => git.clone(
              url: url,
              outputDirectory: outputDirectory,
            ),
          ),
          throwsA(
            isA<ProcessException>().having((e) => e.message, 'message', error),
          ),
        );
      });
    });
  });
}

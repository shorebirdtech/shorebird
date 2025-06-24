import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_process_tools/shorebird_process_tools.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(Git, () {
    late ShorebirdProcessResult processResult;
    late ProcessWrapper process;
    late Git git;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {processRef.overrideWith(() => process)},
      );
    }

    setUp(() {
      processResult = MockShorebirdProcessResult();
      process = MockProcessWrapper();
      git = runWithOverrides(Git.new);

      when(
        () => process.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => processResult);
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
    });

    group('scoped', () {
      test('has access to git reference', () {
        expect(
          runScoped(() => git, values: {gitRef}),
          isA<Git>(),
        );
      });
    });

    group('clone', () {
      const url = 'https://github.com/shorebirdtech/shorebird';
      const outputDirectory = './output';

      test('executes correct command (no args)', () async {
        await runWithOverrides(
          () => git.clone(url: url, outputDirectory: outputDirectory),
        );
        verify(
          () => process.run('git', ['clone', url, outputDirectory]),
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
          () => process.run('git', ['clone', url, ...args, outputDirectory]),
        ).called(1);
      });

      test('throws ProcessException if process exits with error', () async {
        const error = 'oops';
        when(() => processResult.exitCode).thenReturn(ExitCode.software.code);
        when(() => processResult.stderr).thenReturn(error);
        expect(
          () => runWithOverrides(
            () => git.clone(url: url, outputDirectory: outputDirectory),
          ),
          throwsA(
            isA<ProcessException>().having((e) => e.message, 'message', error),
          ),
        );
      });
    });

    group('checkout', () {
      const directory = './output';
      const revision = 'revision';

      test('executes correct command', () async {
        await runWithOverrides(
          () => git.checkout(directory: directory, revision: revision),
        );
        verify(
          () => process.run('git', [
            '-C',
            directory,
            '-c',
            'advice.detachedHead=false',
            'checkout',
            revision,
          ]),
        ).called(1);
      });

      test('throws ProcessException if process exits with error', () async {
        const error = 'oops';
        when(() => processResult.exitCode).thenReturn(ExitCode.software.code);
        when(() => processResult.stderr).thenReturn(error);
        expect(
          () => runWithOverrides(
            () => git.checkout(directory: directory, revision: revision),
          ),
          throwsA(
            isA<ProcessException>().having((e) => e.message, 'message', error),
          ),
        );
      });
    });

    group('fetch', () {
      const directory = 'repository';
      test('executes correct command', () async {
        await expectLater(
          runWithOverrides(() => git.fetch(directory: directory)),
          completes,
        );
        verify(
          () => process.run('git', ['fetch'], workingDirectory: directory),
        ).called(1);
      });

      test('executes correct command w/args', () async {
        final args = ['--tags'];
        await expectLater(
          runWithOverrides(() => git.fetch(directory: directory, args: args)),
          completes,
        );
        verify(
          () => process.run('git', [
            'fetch',
            ...args,
          ], workingDirectory: directory),
        ).called(1);
      });

      test('throws ProcessException if process exits with error', () async {
        const error = 'oops';
        when(() => processResult.exitCode).thenReturn(ExitCode.software.code);
        when(() => processResult.stderr).thenReturn(error);
        expect(
          () => runWithOverrides(() => git.fetch(directory: directory)),
          throwsA(
            isA<ProcessException>().having((e) => e.message, 'message', error),
          ),
        );
      });
    });

    group('forEachRef', () {
      const directory = 'repository';
      const format = '%(refname:short)';
      const pattern = 'refs/remotes/origin/flutter_release/*';
      const output = '''

origin/flutter_release/3.10.0
origin/flutter_release/3.10.1
origin/flutter_release/3.10.2
origin/flutter_release/3.10.3
origin/flutter_release/3.10.4
origin/flutter_release/3.10.5
origin/flutter_release/3.10.6''';
      test('executes correct command', () async {
        when(() => processResult.stdout).thenReturn(output);
        await expectLater(
          runWithOverrides(
            () => git.forEachRef(
              pattern: pattern,
              format: format,
              directory: directory,
            ),
          ),
          completion(equals(output.trim())),
        );
        verify(
          () => process.run('git', [
            'for-each-ref',
            '--format',
            format,
            pattern,
          ], workingDirectory: directory),
        ).called(1);
      });

      test('executes correct command w/contains', () async {
        const contains = 'revision';
        when(() => processResult.stdout).thenReturn(output);
        await expectLater(
          runWithOverrides(
            () => git.forEachRef(
              contains: contains,
              pattern: pattern,
              format: format,
              directory: directory,
            ),
          ),
          completion(equals(output.trim())),
        );
        verify(
          () => process.run('git', [
            'for-each-ref',
            '--contains',
            contains,
            '--format',
            format,
            pattern,
          ], workingDirectory: directory),
        ).called(1);
      });

      test('throws ProcessException if process exits with error', () async {
        const error = 'oops';
        when(() => processResult.exitCode).thenReturn(ExitCode.software.code);
        when(() => processResult.stderr).thenReturn(error);
        expect(
          () => runWithOverrides(
            () => git.forEachRef(
              pattern: pattern,
              format: format,
              directory: directory,
            ),
          ),
          throwsA(
            isA<ProcessException>().having((e) => e.message, 'message', error),
          ),
        );
      });
    });

    group('reset', () {
      const directory = './output';
      const revision = 'revision';

      test('executes correct command', () async {
        await expectLater(
          runWithOverrides(
            () => git.reset(directory: directory, revision: revision),
          ),
          completes,
        );
        verify(
          () => process.run('git', [
            'reset',
            revision,
          ], workingDirectory: directory),
        ).called(1);
      });

      test('executes correct command w/args', () async {
        const args = ['--hard'];
        await expectLater(
          runWithOverrides(
            () =>
                git.reset(directory: directory, revision: revision, args: args),
          ),
          completes,
        );
        verify(
          () => process.run('git', [
            'reset',
            ...args,
            revision,
          ], workingDirectory: directory),
        ).called(1);
      });

      test('throws ProcessException if process exits with error', () async {
        const error = 'oops';
        when(() => processResult.exitCode).thenReturn(ExitCode.software.code);
        when(() => processResult.stderr).thenReturn(error);
        expect(
          () => runWithOverrides(
            () => git.reset(directory: directory, revision: revision),
          ),
          throwsA(
            isA<ProcessException>().having((e) => e.message, 'message', error),
          ),
        );
      });
    });

    group('remote', () {
      const directory = './output';

      test('executes correct command', () async {
        await expectLater(
          runWithOverrides(() => git.remote(directory: directory)),
          completes,
        );
        verify(
          () => process.run('git', ['remote'], workingDirectory: directory),
        ).called(1);
      });

      test('executes correct command w/args', () async {
        const args = ['prune', 'origin'];
        await expectLater(
          runWithOverrides(() => git.remote(directory: directory, args: args)),
          completes,
        );
        verify(
          () => process.run('git', [
            'remote',
            ...args,
          ], workingDirectory: directory),
        ).called(1);
      });

      test('throws ProcessException if process exits with error', () async {
        const error = 'oops';
        when(() => processResult.exitCode).thenReturn(ExitCode.software.code);
        when(() => processResult.stderr).thenReturn(error);
        expect(
          () => runWithOverrides(() => git.remote(directory: directory)),
          throwsA(
            isA<ProcessException>().having((e) => e.message, 'message', error),
          ),
        );
      });
    });

    group('revParse', () {
      const directory = './output';
      const revision = 'revision';

      test('executes correct command', () async {
        const output = 'revision';
        when(() => processResult.stdout).thenReturn(output);
        await expectLater(
          runWithOverrides(
            () => git.revParse(directory: directory, revision: revision),
          ),
          completion(equals(output)),
        );
        verify(
          () => process.run('git', [
            'rev-parse',
            '--verify',
            revision,
          ], workingDirectory: directory),
        ).called(1);
      });

      test('throws ProcessException if process exits with error', () async {
        const error = 'oops';
        when(() => processResult.exitCode).thenReturn(ExitCode.software.code);
        when(() => processResult.stderr).thenReturn(error);
        expect(
          () => runWithOverrides(
            () => git.revParse(directory: directory, revision: revision),
          ),
          throwsA(
            isA<ProcessException>().having((e) => e.message, 'message', error),
          ),
        );
      });
    });

    group('status', () {
      const directory = './output';

      test('executes correct command', () async {
        const output = 'status';
        when(() => processResult.stdout).thenReturn(output);
        await expectLater(
          runWithOverrides(() => git.status(directory: directory)),
          completion(equals(output)),
        );
        verify(
          () => process.run('git', ['status'], workingDirectory: directory),
        ).called(1);
      });

      test('executes correct command w/args', () async {
        const output = 'status';
        const args = ['--porcelain'];
        when(() => processResult.stdout).thenReturn(output);
        await expectLater(
          runWithOverrides(() => git.status(directory: directory, args: args)),
          completion(equals(output)),
        );
        verify(
          () => process.run('git', [
            'status',
            ...args,
          ], workingDirectory: directory),
        ).called(1);
      });

      test('throws ProcessException if process exits with error', () async {
        const error = 'oops';
        when(() => processResult.exitCode).thenReturn(ExitCode.software.code);
        when(() => processResult.stderr).thenReturn(error);
        expect(
          () => runWithOverrides(() => git.status(directory: directory)),
          throwsA(
            isA<ProcessException>().having((e) => e.message, 'message', error),
          ),
        );
      });
    });

    group('symbolicRef', () {
      setUp(() {
        when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
        when(() => processResult.stdout).thenReturn('refs/heads/main');
      });

      test('executes correct command', () async {
        final directory = Directory.current;
        await expectLater(
          runWithOverrides(
            () => git.symbolicRef(directory: directory, revision: '1234'),
          ),
          completion(equals('refs/heads/main')),
        );
        verify(
          () => process.run('git', [
            'symbolic-ref',
            '1234',
          ], workingDirectory: directory.path),
        ).called(1);
      });

      test('defaults to HEAD if no revision is provided', () async {
        final directory = Directory.current;
        await expectLater(
          runWithOverrides(() => git.symbolicRef(directory: directory)),
          completion(equals('refs/heads/main')),
        );
        verify(
          () => process.run('git', [
            'symbolic-ref',
            'HEAD',
          ], workingDirectory: directory.path),
        ).called(1);
      });
    });

    group('currentBranch', () {
      setUp(() {
        when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
        when(() => processResult.stdout).thenReturn('''
refs/heads/main
''');
      });

      test('removes refs/heads from branch name', () async {
        final directory = Directory.current;
        await expectLater(
          runWithOverrides(() => git.currentBranch(directory: directory)),
          completion(equals('main')),
        );
      });
    });

    group('isGitRepo', () {
      group('when git exits with code 0', () {
        setUp(() {
          when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
        });

        test('returns true', () async {
          final directory = Directory.current;
          final result = await runWithOverrides(
            () => git.isGitRepo(directory: directory),
          );
          expect(result, isTrue);
        });
      });

      group('when git exits with nonzero code', () {
        setUp(() {
          when(() => processResult.exitCode).thenReturn(ExitCode.software.code);
        });

        test('returns true', () async {
          final directory = Directory.current;
          final result = await runWithOverrides(
            () => git.isGitRepo(directory: directory),
          );
          expect(result, isFalse);
        });
      });
    });

    group('isFileTracked', () {
      group('when git exits with code 0', () {
        setUp(() {
          when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
        });

        test('returns true', () async {
          final result = await runWithOverrides(
            () => git.isFileTracked(file: File('file')),
          );
          expect(result, isTrue);
        });
      });

      group('when git exits with nonzero code', () {
        setUp(() {
          when(() => processResult.exitCode).thenReturn(ExitCode.software.code);
        });

        test('returns true', () async {
          final result = await runWithOverrides(
            () => git.isFileTracked(file: File('file')),
          );
          expect(result, isFalse);
        });
      });
    });
  });
}

import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

class _MockProcess extends Mock implements Process {}

class _MockProcessResult extends Mock implements ProcessResult {}

class _MockProcessWrapper extends Mock implements ProcessWrapper {}

void main() {
  group('ShorebirdProcess', () {
    late ProcessWrapper processWrapper;
    late Process startProcess;
    late ProcessResult runProcessResult;

    setUp(() {
      processWrapper = _MockProcessWrapper();
      runProcessResult = _MockProcessResult();
      startProcess = _MockProcess();

      ShorebirdProcess.processWrapper = processWrapper;

      when(() => processWrapper.run).thenReturn(
        (
          executable,
          arguments, {
          bool runInShell = false,
          String? workingDirectory,
          bool resolveExecutables = true,
        }) async {
          return runProcessResult;
        },
      );

      when(() => processWrapper.start).thenReturn(
        (
          executable,
          arguments, {
          bool runInShell = false,
        }) async {
          return startProcess;
        },
      );
    });

    group('run', () {
      test('forwards non-flutter executables to Process.run', () async {
        await ShorebirdProcess.run(
          'git',
          ['pull'],
          runInShell: true,
          workingDirectory: '~',
        );

        verify(
          () => processWrapper.run(
            'git',
            ['pull'],
            runInShell: true,
            workingDirectory: '~',
          ),
        ).called(1);
      });

      test('replaces "flutter" with our local flutter', () async {
        await ShorebirdProcess.run(
          'flutter',
          ['--version'],
          runInShell: true,
          workingDirectory: '~',
        );

        verify(
          () => processWrapper.run(
            'flutter/bin/flutter',
            ['--version'],
            runInShell: true,
            workingDirectory: '~',
          ),
        ).called(1);
      });

      test(
          'does not replace flutter with our local flutter if'
          ' resolveExecutables is false', () async {
        await ShorebirdProcess.run(
          'flutter',
          ['--version'],
          runInShell: true,
          workingDirectory: '~',
          resolveExecutables: false,
        );

        verify(
          () => processWrapper.run(
            'flutter',
            ['--version'],
            runInShell: true,
            workingDirectory: '~',
          ),
        ).called(1);
      });
    });

    group('start', () {
      test('forwards non-flutter executables to Process.run', () async {
        await ShorebirdProcess.start('git', ['pull'], runInShell: true);

        verify(() => processWrapper.start('git', ['pull'], runInShell: true))
            .called(1);
      });

      test('replaces "flutter" with our local flutter', () async {
        await ShorebirdProcess.start('flutter', ['run'], runInShell: true);

        verify(
          () => processWrapper.start(
            'flutter/bin/flutter',
            ['run'],
            runInShell: true,
          ),
        ).called(1);
      });

      test(
          'does not replace flutter with our local flutter if'
          ' resolveExecutables is false', () async {
        await ShorebirdProcess.start(
          'flutter',
          ['--version'],
          runInShell: true,
          resolveExecutables: false,
        );

        verify(
          () => processWrapper.start(
            'flutter',
            ['--version'],
            runInShell: true,
          ),
        ).called(1);
      });
    });
  });
}

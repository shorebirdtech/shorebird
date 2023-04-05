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

      ShorebirdProcess.processWrapper = _MockProcessWrapper();

      when(() => processWrapper.run).thenReturn(
        (
          executable,
          arguments, {
          bool runInShell = false,
          String? workingDirectory,
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
        await ShorebirdProcess.run('git', ['pull']);

        verify(() => processWrapper.run('git', ['pull'])).called(1);
      });

      test('replaces "flutter" with our local flutter', () async {
        await ShorebirdProcess.run('flutter', ['--version']);

        verify(() => processWrapper.run('flutter/bin/flutter', ['--version']))
            .called(1);
      });
    });

    group('start', () {
      test('forwards non-flutter executables to Process.run', () async {
        await ShorebirdProcess.start('git', ['pull']);

        verify(() => processWrapper.start('git', ['pull'])).called(1);
      });

      test('replaces "flutter" with our local flutter', () async {
        await ShorebirdProcess.start('flutter', ['run']);

        verify(() => processWrapper.start('flutter/bin/flutter', ['run']))
            .called(1);
      });
    });
  });
}

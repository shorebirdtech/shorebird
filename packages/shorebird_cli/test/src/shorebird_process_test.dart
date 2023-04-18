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
    late ShorebirdProcess shorebirdProcess;

    setUp(() {
      processWrapper = _MockProcessWrapper();
      runProcessResult = _MockProcessResult();
      startProcess = _MockProcess();
      shorebirdProcess = ShorebirdProcess(processWrapper);

      when(
        () => processWrapper.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          environment: any(named: 'environment'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => runProcessResult);

      when(
        () => processWrapper.start(
          any(),
          any(),
          environment: any(named: 'environment'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => startProcess);
    });

    group('run', () {
      test('forwards non-flutter executables to Process.run', () async {
        await shorebirdProcess.run(
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
            environment: {},
            workingDirectory: '~',
          ),
        ).called(1);
      });

      test('replaces "flutter" with our local flutter', () async {
        await shorebirdProcess.run(
          'flutter',
          ['--version'],
          runInShell: true,
          workingDirectory: '~',
        );

        verify(
          () => processWrapper.run(
            any(that: contains('bin/cache/flutter/bin/flutter')),
            ['--version'],
            runInShell: true,
            environment: {
              'FLUTTER_STORAGE_BASE_URL': 'https://download.shorebird.dev/',
            },
            workingDirectory: '~',
          ),
        ).called(1);
      });

      test(
          'does not replace flutter with our local flutter if'
          ' useVendedFlutter is false', () async {
        await shorebirdProcess.run(
          'flutter',
          ['--version'],
          runInShell: true,
          workingDirectory: '~',
          useVendedFlutter: false,
        );

        verify(
          () => processWrapper.run(
            'flutter',
            ['--version'],
            runInShell: true,
            environment: {},
            workingDirectory: '~',
          ),
        ).called(1);
      });

      test('Updates environment if useVendedFlutter is true', () async {
        await shorebirdProcess.run(
          'flutter',
          ['--version'],
          runInShell: true,
          workingDirectory: '~',
          useVendedFlutter: false,
          environment: {'ENV_VAR': 'asdfasdf'},
        );

        verify(
          () => processWrapper.run(
            'flutter',
            ['--version'],
            runInShell: true,
            workingDirectory: '~',
            environment: {'ENV_VAR': 'asdfasdf'},
          ),
        ).called(1);
      });

      test(
        'Makes no changes to environment if useVendedFlutter is false',
        () async {
          await shorebirdProcess.run(
            'flutter',
            ['--version'],
            runInShell: true,
            workingDirectory: '~',
            useVendedFlutter: false,
            environment: {'ENV_VAR': 'asdfasdf'},
          );

          verify(
            () => processWrapper.run(
              'flutter',
              ['--version'],
              runInShell: true,
              workingDirectory: '~',
              environment: {'ENV_VAR': 'asdfasdf'},
            ),
          ).called(1);
        },
      );
    });

    group('start', () {
      test('forwards non-flutter executables to Process.run', () async {
        await shorebirdProcess.start('git', ['pull'], runInShell: true);

        verify(
          () => processWrapper.start(
            'git',
            ['pull'],
            runInShell: true,
            environment: {},
          ),
        ).called(1);
      });

      test('replaces "flutter" with our local flutter', () async {
        await shorebirdProcess.start('flutter', ['run'], runInShell: true);

        verify(
          () => processWrapper.start(
            any(that: contains('bin/cache/flutter/bin/flutter')),
            ['run'],
            runInShell: true,
            environment: {
              'FLUTTER_STORAGE_BASE_URL': 'https://download.shorebird.dev/',
            },
          ),
        ).called(1);
      });

      test(
          'does not replace flutter with our local flutter if'
          ' useVendedFlutter is false', () async {
        await shorebirdProcess.start(
          'flutter',
          ['--version'],
          runInShell: true,
          useVendedFlutter: false,
        );

        verify(
          () => processWrapper.start(
            'flutter',
            ['--version'],
            runInShell: true,
            environment: {},
          ),
        ).called(1);
      });
    });

    test('Updates environment if useVendedFlutter is true', () async {
      await shorebirdProcess.start(
        'flutter',
        ['--version'],
        runInShell: true,
        environment: {'ENV_VAR': 'asdfasdf'},
      );

      verify(
        () => processWrapper.start(
          any(that: contains('bin/cache/flutter/bin/flutter')),
          ['--version'],
          runInShell: true,
          environment: {
            'ENV_VAR': 'asdfasdf',
            'FLUTTER_STORAGE_BASE_URL': 'https://download.shorebird.dev/',
          },
        ),
      ).called(1);
    });

    test(
      'Makes no changes to environment if useVendedFlutter is false',
      () async {
        await shorebirdProcess.start(
          'flutter',
          ['--version'],
          runInShell: true,
          useVendedFlutter: false,
          environment: {'hello': 'world'},
        );

        verify(
          () => processWrapper.start(
            'flutter',
            ['--version'],
            runInShell: true,
            environment: {'hello': 'world'},
          ),
        ).called(1);
      },
    );
  });
}

import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_engine_config.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group('ShorebirdProcess', () {
    const flutterStorageBaseUrlEnv = {
      'FLUTTER_STORAGE_BASE_URL': 'https://download.shorebird.dev',
    };

    late EngineConfig engineConfig;
    late Logger logger;
    late ProcessWrapper processWrapper;
    late Process startProcess;
    late ShorebirdProcessResult runProcessResult;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess shorebirdProcess;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          engineConfigRef.overrideWith(() => engineConfig),
          loggerRef.overrideWith(() => logger),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      engineConfig = const EngineConfig.empty();
      logger = MockLogger();
      processWrapper = MockProcessWrapper();
      runProcessResult = MockProcessResult();
      startProcess = MockProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdProcess = runWithOverrides(
        () => ShorebirdProcess(processWrapper: processWrapper),
      );

      when(
        () => shorebirdEnv.flutterBinaryFile,
      ).thenReturn(File(p.join('bin', 'cache', 'flutter', 'bin', 'flutter')));

      when(() => runProcessResult.stderr).thenReturn('');
      when(() => runProcessResult.stdout).thenReturn('');
      when(() => runProcessResult.exitCode).thenReturn(ExitCode.success.code);

      when(() => logger.level).thenReturn(Level.info);
    });

    test('ShorebirdProcessResult can be instantiated as a const', () {
      expect(
        () => const ShorebirdProcessResult(exitCode: 0, stdout: '', stderr: ''),
        returnsNormally,
      );
    });

    group('run', () {
      setUp(() {
        when(
          () => processWrapper.run(
            any(),
            any(),
            runInShell: any(named: 'runInShell'),
            environment: any(named: 'environment'),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => runProcessResult);
      });

      test('forwards non-flutter executables to Process.run', () async {
        await runWithOverrides(
          () => shorebirdProcess.run(
            'git',
            ['pull'],
            runInShell: true,
            workingDirectory: '~',
          ),
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
        await runWithOverrides(
          () => shorebirdProcess.run(
            'flutter',
            ['--version'],
            runInShell: true,
            workingDirectory: '~',
          ),
        );

        verify(
          () => processWrapper.run(
            any(
              that: contains(
                p.join('bin', 'cache', 'flutter', 'bin', 'flutter'),
              ),
            ),
            ['--version'],
            runInShell: true,
            environment: flutterStorageBaseUrlEnv,
            workingDirectory: '~',
          ),
        ).called(1);
      });

      test(
          'does not replace flutter with our local flutter if'
          ' useVendedFlutter is false', () async {
        await runWithOverrides(
          () => shorebirdProcess.run(
            'flutter',
            ['--version'],
            runInShell: true,
            workingDirectory: '~',
            useVendedFlutter: false,
          ),
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
        await runWithOverrides(
          () => shorebirdProcess.run(
            'flutter',
            ['--version'],
            runInShell: true,
            workingDirectory: '~',
            useVendedFlutter: false,
            environment: {'ENV_VAR': 'asdfasdf'},
          ),
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
          await runWithOverrides(
            () => shorebirdProcess.run(
              'flutter',
              ['--version'],
              runInShell: true,
              workingDirectory: '~',
              useVendedFlutter: false,
              environment: {'ENV_VAR': 'asdfasdf'},
            ),
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

      test('adds local-engine arguments if set', () async {
        engineConfig = EngineConfig(
          localEngineSrcPath: 'path/to/engine/src',
          localEngine: 'android_release_arm64',
          localEngineHost: 'host_release',
        );
        final localEngineSrcPath = p.join('path', 'to', 'engine', 'src');
        shorebirdProcess = ShorebirdProcess(
          processWrapper: processWrapper,
        );

        await runWithOverrides(() => shorebirdProcess.run('flutter', []));

        verify(
          () => processWrapper.run(
            any(),
            [
              '--local-engine-src-path=$localEngineSrcPath',
              '--local-engine=android_release_arm64',
              '--local-engine-host=host_release',
            ],
            runInShell: any(named: 'runInShell'),
            environment: any(named: 'environment'),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).called(1);
      });

      group('when log level is verbose', () {
        setUp(() {
          when(() => logger.level).thenReturn(Level.verbose);
        });

        test('passes --verbose to flutter executable', () async {
          await runWithOverrides(
            () => shorebirdProcess.run('flutter', []),
          );

          verify(
            () => processWrapper.run(
              any(),
              ['--verbose'],
              runInShell: any(named: 'runInShell'),
              environment: any(named: 'environment'),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).called(1);
        });

        group('when result has non-zero exit code', () {
          setUp(() {
            when(() => runProcessResult.exitCode).thenReturn(1);
            when(() => runProcessResult.stdout).thenReturn('out');
            when(() => runProcessResult.stderr).thenReturn('err');
          });

          test('logs stdout and stderr if present', () async {
            await runWithOverrides(() => shorebirdProcess.run('flutter', []));

            verify(() => logger.detail(any(that: contains('stdout'))))
                .called(1);
            verify(() => logger.detail(any(that: contains('stderr'))))
                .called(1);
          });
        });
      });
    });

    group('runSync', () {
      setUp(() {
        when(
          () => processWrapper.runSync(
            any(),
            any(),
            runInShell: any(named: 'runInShell'),
            environment: any(named: 'environment'),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenReturn(runProcessResult);
      });

      test('forwards non-flutter executables to Process.runSync', () async {
        runWithOverrides(
          () => shorebirdProcess.runSync(
            'git',
            ['pull'],
            runInShell: true,
            workingDirectory: '~',
          ),
        );

        verify(
          () => processWrapper.runSync(
            'git',
            ['pull'],
            runInShell: true,
            environment: {},
            workingDirectory: '~',
          ),
        ).called(1);
      });

      test('replaces "flutter" with our local flutter', () {
        runWithOverrides(
          () => shorebirdProcess.runSync(
            'flutter',
            ['--version'],
            runInShell: true,
            workingDirectory: '~',
          ),
        );

        verify(
          () => processWrapper.runSync(
            any(
              that: contains(
                p.join('bin', 'cache', 'flutter', 'bin', 'flutter'),
              ),
            ),
            ['--version'],
            runInShell: true,
            environment: flutterStorageBaseUrlEnv,
            workingDirectory: '~',
          ),
        ).called(1);
      });

      test(
          '''does not replace flutter with our local flutter if useVendedFlutter is false''',
          () {
        runWithOverrides(
          () => shorebirdProcess.runSync(
            'flutter',
            ['--version'],
            runInShell: true,
            workingDirectory: '~',
            useVendedFlutter: false,
          ),
        );

        verify(
          () => processWrapper.runSync(
            'flutter',
            ['--version'],
            runInShell: true,
            environment: {},
            workingDirectory: '~',
          ),
        ).called(1);
      });

      test('Updates environment if useVendedFlutter is true', () {
        runWithOverrides(
          () => shorebirdProcess.runSync(
            'flutter',
            ['--version'],
            runInShell: true,
            workingDirectory: '~',
            useVendedFlutter: false,
            environment: {'ENV_VAR': 'asdfasdf'},
          ),
        );

        verify(
          () => processWrapper.runSync(
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
        () {
          runWithOverrides(
            () => shorebirdProcess.runSync(
              'flutter',
              ['--version'],
              runInShell: true,
              workingDirectory: '~',
              useVendedFlutter: false,
              environment: {'ENV_VAR': 'asdfasdf'},
            ),
          );

          verify(
            () => processWrapper.runSync(
              'flutter',
              ['--version'],
              runInShell: true,
              workingDirectory: '~',
              environment: {'ENV_VAR': 'asdfasdf'},
            ),
          ).called(1);
        },
      );

      group('when log level is verbose', () {
        setUp(() {
          when(() => logger.level).thenReturn(Level.verbose);
        });

        test('passes --verbose to flutter executable', () {
          runWithOverrides(
            () => shorebirdProcess.runSync('flutter', []),
          );

          verify(
            () => processWrapper.runSync(
              any(),
              ['--verbose'],
              runInShell: any(named: 'runInShell'),
              environment: any(named: 'environment'),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).called(1);
        });

        group('when result has non-zero exit code', () {
          setUp(() {
            when(() => runProcessResult.exitCode).thenReturn(1);
            when(() => runProcessResult.stdout).thenReturn('out');
            when(() => runProcessResult.stderr).thenReturn('err');
          });

          test('logs stdout and stderr if present', () {
            runWithOverrides(() => shorebirdProcess.runSync('flutter', []));

            verify(() => logger.detail(any(that: contains('stdout'))))
                .called(1);
            verify(() => logger.detail(any(that: contains('stderr'))))
                .called(1);
          });
        });
      });
    });

    group('start', () {
      setUp(() {
        when(
          () => processWrapper.start(
            any(),
            any(),
            environment: any(named: 'environment'),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer((_) async => startProcess);
      });

      test('forwards non-flutter executables to Process.run', () async {
        await runWithOverrides(
          () => shorebirdProcess.start(
            'git',
            ['pull'],
            runInShell: true,
          ),
        );

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
        await runWithOverrides(
          () => shorebirdProcess.start('flutter', ['run'], runInShell: true),
        );

        verify(
          () => processWrapper.start(
            any(
              that: contains(
                p.join('bin', 'cache', 'flutter', 'bin', 'flutter'),
              ),
            ),
            ['run'],
            runInShell: true,
            environment: flutterStorageBaseUrlEnv,
          ),
        ).called(1);
      });

      test(
          'does not replace flutter with our local flutter if'
          ' useVendedFlutter is false', () async {
        await runWithOverrides(
          () => shorebirdProcess.start(
            'flutter',
            ['--version'],
            runInShell: true,
            useVendedFlutter: false,
          ),
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
      test('Updates environment if useVendedFlutter is true', () async {
        await runWithOverrides(
          () => shorebirdProcess.start(
            'flutter',
            ['--version'],
            runInShell: true,
            environment: {'ENV_VAR': 'asdfasdf'},
          ),
        );

        verify(
          () => processWrapper.start(
            any(
              that: contains(
                p.join('bin', 'cache', 'flutter', 'bin', 'flutter'),
              ),
            ),
            ['--version'],
            runInShell: true,
            environment: {
              'ENV_VAR': 'asdfasdf',
              ...flutterStorageBaseUrlEnv,
            },
          ),
        ).called(1);
      });

      test(
        'Makes no changes to environment if useVendedFlutter is false',
        () async {
          await runWithOverrides(
            () => shorebirdProcess.start(
              'flutter',
              ['--version'],
              runInShell: true,
              useVendedFlutter: false,
              environment: {'hello': 'world'},
            ),
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
  });
}

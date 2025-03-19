// cspell:ignore asdfasdf
import 'dart:io' hide Platform;

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
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
    late ShorebirdLogger logger;
    late Platform platform;
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
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      engineConfig = const EngineConfig.empty();
      logger = MockShorebirdLogger();
      platform = MockPlatform();
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

      when(() => runProcessResult.stderr).thenReturn('stderr');
      when(() => runProcessResult.stdout).thenReturn('stdout');
      when(() => runProcessResult.exitCode).thenReturn(ExitCode.success.code);

      when(() => logger.level).thenReturn(Level.info);

      when(() => platform.isWindows).thenReturn(false);
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
            environment: any(named: 'environment'),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).thenAnswer((_) async => runProcessResult);
      });

      test('can override runInShell', () async {
        await runWithOverrides(
          () => shorebirdProcess.run('git', ['pull'], runInShell: true),
        );

        verify(
          () => processWrapper.run(
            'git',
            ['pull'],
            environment: {},
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).called(1);
      });

      test('forwards non-flutter executables to Process.run', () async {
        await runWithOverrides(
          () => shorebirdProcess.run('git', ['pull'], workingDirectory: '~'),
        );

        verify(
          () => processWrapper.run(
            'git',
            ['pull'],
            environment: {},
            workingDirectory: '~',
          ),
        ).called(1);
      });

      test('sanitizes executable on windows', () {
        when(() => platform.isWindows).thenReturn(true);
        const executable =
            r'C:\Program Files\Android\Android Studio\jbr\bin\java.exe';
        runWithOverrides(() => shorebirdProcess.run(executable, ['--version']));
        verify(
          () => processWrapper.run(
            '"$executable"',
            ['--version'],
            environment: any(named: 'environment'),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).called(1);
      });

      test('replaces "flutter" with our local flutter', () async {
        await runWithOverrides(
          () => shorebirdProcess.run('flutter', [
            '--version',
          ], workingDirectory: '~'),
        );

        verify(
          () => processWrapper.run(
            any(
              that: contains(
                p.join('bin', 'cache', 'flutter', 'bin', 'flutter'),
              ),
            ),
            ['--version'],
            environment: flutterStorageBaseUrlEnv,
            workingDirectory: '~',
          ),
        ).called(1);
      });

      test('does not replace flutter with our local flutter if'
          ' useVendedFlutter is false', () async {
        await runWithOverrides(
          () => shorebirdProcess.run(
            'flutter',
            ['--version'],
            workingDirectory: '~',
            useVendedFlutter: false,
          ),
        );

        verify(
          () => processWrapper.run(
            'flutter',
            ['--version'],
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
            workingDirectory: '~',
            useVendedFlutter: false,
            environment: {'ENV_VAR': 'asdfasdf'},
          ),
        );

        verify(
          () => processWrapper.run(
            'flutter',
            ['--version'],
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
              workingDirectory: '~',
              useVendedFlutter: false,
              environment: {'ENV_VAR': 'asdfasdf'},
            ),
          );

          verify(
            () => processWrapper.run(
              'flutter',
              ['--version'],
              workingDirectory: '~',
              environment: {'ENV_VAR': 'asdfasdf'},
            ),
          ).called(1);
        },
      );

      test('adds local-engine arguments if set', () async {
        engineConfig = EngineConfig(
          localEngineSrcPath: p.join('path', 'to', 'engine', 'src'),
          localEngine: 'android_release_arm64',
          localEngineHost: 'host_release',
        );
        final localEngineSrcPath = p.join('path', 'to', 'engine', 'src');
        shorebirdProcess = ShorebirdProcess(processWrapper: processWrapper);

        await runWithOverrides(() => shorebirdProcess.run('flutter', []));

        verify(
          () => processWrapper.run(
            any(),
            [
              '--local-engine-src-path=$localEngineSrcPath',
              '--local-engine=android_release_arm64',
              '--local-engine-host=host_release',
            ],
            environment: any(named: 'environment'),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).called(1);
      });

      test('logs stdout and stderr', () async {
        await runWithOverrides(() => shorebirdProcess.run('flutter', []));

        verify(() => logger.detail(any(that: contains('stdout')))).called(1);
        verify(() => logger.detail(any(that: contains('stderr')))).called(1);
      });
    });

    group('runSync', () {
      setUp(() {
        when(
          () => processWrapper.runSync(
            any(),
            any(),
            environment: any(named: 'environment'),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenReturn(runProcessResult);
      });

      test('forwards non-flutter executables to Process.runSync', () async {
        runWithOverrides(
          () =>
              shorebirdProcess.runSync('git', ['pull'], workingDirectory: '~'),
        );

        verify(
          () => processWrapper.runSync(
            'git',
            ['pull'],
            environment: {},
            workingDirectory: '~',
          ),
        ).called(1);
      });

      test('sanitizes executable on windows', () {
        when(() => platform.isWindows).thenReturn(true);
        const executable =
            r'C:\Program Files\Android\Android Studio\jbr\bin\java.exe';
        runWithOverrides(
          () => shorebirdProcess.runSync(executable, ['--version']),
        );
        verify(
          () => processWrapper.runSync(
            '"$executable"',
            ['--version'],
            environment: any(named: 'environment'),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).called(1);
      });

      test('replaces "flutter" with our local flutter', () {
        runWithOverrides(
          () => shorebirdProcess.runSync('flutter', [
            '--version',
          ], workingDirectory: '~'),
        );

        verify(
          () => processWrapper.runSync(
            any(
              that: contains(
                p.join('bin', 'cache', 'flutter', 'bin', 'flutter'),
              ),
            ),
            ['--version'],
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
              workingDirectory: '~',
              useVendedFlutter: false,
            ),
          );

          verify(
            () => processWrapper.runSync(
              'flutter',
              ['--version'],
              environment: {},
              workingDirectory: '~',
            ),
          ).called(1);
        },
      );

      test('Updates environment if useVendedFlutter is true', () {
        runWithOverrides(
          () => shorebirdProcess.runSync(
            'flutter',
            ['--version'],
            workingDirectory: '~',
            useVendedFlutter: false,
            environment: {'ENV_VAR': 'asdfasdf'},
          ),
        );

        verify(
          () => processWrapper.runSync(
            'flutter',
            ['--version'],
            workingDirectory: '~',
            environment: {'ENV_VAR': 'asdfasdf'},
          ),
        ).called(1);
      });

      test('Makes no changes to environment if useVendedFlutter is false', () {
        runWithOverrides(
          () => shorebirdProcess.runSync(
            'flutter',
            ['--version'],
            workingDirectory: '~',
            useVendedFlutter: false,
            environment: {'ENV_VAR': 'asdfasdf'},
          ),
        );

        verify(
          () => processWrapper.runSync(
            'flutter',
            ['--version'],
            workingDirectory: '~',
            environment: {'ENV_VAR': 'asdfasdf'},
          ),
        ).called(1);
      });

      group('when log level is verbose', () {
        setUp(() {
          when(() => logger.level).thenReturn(Level.verbose);
        });

        test('passes --verbose to flutter executable', () {
          runWithOverrides(() => shorebirdProcess.runSync('flutter', []));

          verify(
            () => processWrapper.runSync(
              any(),
              ['--verbose'],
              environment: any(named: 'environment'),
              workingDirectory: any(named: 'workingDirectory'),
            ),
          ).called(1);
        });
      });

      group('when result has non-zero exit code', () {
        setUp(() {
          when(() => runProcessResult.exitCode).thenReturn(1);
          when(() => runProcessResult.stdout).thenReturn('out');
          when(() => runProcessResult.stderr).thenReturn('err');
        });

        test('logs stdout and stderr if present', () {
          runWithOverrides(() => shorebirdProcess.runSync('flutter', []));

          verify(() => logger.detail(any(that: contains('stdout')))).called(1);
          verify(() => logger.detail(any(that: contains('stderr')))).called(1);
        });
      });
    });

    group('stream', () {
      late Process streamProcess;

      setUp(() {
        streamProcess = MockProcess();
        when(
          () => processWrapper.start(
            any(),
            any(),
            environment: any(named: 'environment'),
            mode: ProcessStartMode.inheritStdio,
          ),
        ).thenAnswer((_) async => streamProcess);
        when(
          () => streamProcess.exitCode,
        ).thenAnswer((_) async => ExitCode.success.code);
      });

      test('proxies to start with correct mode', () async {
        await expectLater(
          runWithOverrides(() => shorebirdProcess.stream('git', ['pull'])),
          completion(equals(ExitCode.success.code)),
        );

        verify(
          () => processWrapper.start(
            'git',
            ['pull'],
            environment: {},
            mode: ProcessStartMode.inheritStdio,
          ),
        ).called(1);
      });
    });

    group('start', () {
      setUp(() {
        when(
          () => processWrapper.start(
            any(),
            any(),
            environment: any(named: 'environment'),
          ),
        ).thenAnswer((_) async => startProcess);
      });

      test('forwards non-flutter executables to Process.run', () async {
        await runWithOverrides(() => shorebirdProcess.start('git', ['pull']));

        verify(
          () => processWrapper.start('git', ['pull'], environment: {}),
        ).called(1);
      });

      test('sanitizes executable on windows', () {
        when(() => platform.isWindows).thenReturn(true);
        const executable =
            r'C:\Program Files\Android\Android Studio\jbr\bin\java.exe';
        runWithOverrides(
          () => shorebirdProcess.start(executable, ['--version']),
        );
        verify(
          () => processWrapper.start(
            '"$executable"',
            ['--version'],
            environment: any(named: 'environment'),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).called(1);
      });

      test('replaces "flutter" with our local flutter', () async {
        await runWithOverrides(
          () => shorebirdProcess.start('flutter', ['run']),
        );

        verify(
          () => processWrapper.start(
            any(
              that: contains(
                p.join('bin', 'cache', 'flutter', 'bin', 'flutter'),
              ),
            ),
            ['run'],
            environment: flutterStorageBaseUrlEnv,
          ),
        ).called(1);
      });

      test('does not replace flutter with our local flutter if'
          ' useVendedFlutter is false', () async {
        await runWithOverrides(
          () => shorebirdProcess.start('flutter', [
            '--version',
          ], useVendedFlutter: false),
        );

        verify(
          () => processWrapper.start('flutter', ['--version'], environment: {}),
        ).called(1);
      });
      test('Updates environment if useVendedFlutter is true', () async {
        await runWithOverrides(
          () => shorebirdProcess.start(
            'flutter',
            ['--version'],
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
            environment: {'ENV_VAR': 'asdfasdf', ...flutterStorageBaseUrlEnv},
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
              useVendedFlutter: false,
              environment: {'hello': 'world'},
            ),
          );

          verify(
            () => processWrapper.start(
              'flutter',
              ['--version'],
              environment: {'hello': 'world'},
            ),
          ).called(1);
        },
      );
    });
  });
}

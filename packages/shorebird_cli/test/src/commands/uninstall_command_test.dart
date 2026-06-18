import 'dart:io' hide Platform;

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(ProcessStartMode.normal);
  });

  group('uninstall', () {
    late ShorebirdLogger logger;
    late Progress progress;
    late Platform platform;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess shorebirdProcess;
    late UninstallCommand command;
    late Directory shorebirdRoot;
    late Directory homeDirectory;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          processRef.overrideWith(() => shorebirdProcess),
        },
      );
    }

    setUp(() {
      logger = MockShorebirdLogger();
      progress = MockProgress();
      platform = MockPlatform();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdProcess = MockShorebirdProcess();

      shorebirdRoot = Directory.systemTemp.createTempSync();
      homeDirectory = Directory.systemTemp.createTempSync();

      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);

      when(() => platform.isWindows).thenReturn(false);
      when(() => platform.environment).thenReturn({'HOME': homeDirectory.path});

      when(() => logger.confirm(any())).thenReturn(true);
      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => shorebirdProcess.run(
          any(),
          any(),
        ),
      ).thenAnswer(
        (_) async => const ShorebirdProcessResult(
          exitCode: 0,
          stdout: '',
          stderr: '',
        ),
      );

      when(
        () => shorebirdProcess.start(
          any(),
          any(),
          mode: any(named: 'mode'),
        ),
      ).thenAnswer((_) async => MockProcess());

      command = runWithOverrides(UninstallCommand.new);
    });

    test('can be instantiated', () {
      expect(command, isNotNull);
    });

    test('aborts when user does not confirm', () async {
      when(() => logger.confirm(any())).thenReturn(false);

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('Aborting.')).called(1);
      verifyNever(() => logger.progress('Uninstalling Shorebird'));
    });

    test('returns software error on failure', () async {
      when(() => platform.isWindows).thenThrow(Exception('oops'));

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(() => progress.fail()).called(1);
      verify(
        () => logger.err('Failed to uninstall Shorebird: Exception: oops'),
      ).called(1);
    });

    group('windows', () {
      setUp(() {
        when(() => platform.isWindows).thenReturn(true);
        when(() => platform.environment).thenReturn({
          'Path':
              r'C:\Windows\System32;C:\Users\admin\.shorebird\bin;C:\Flutter\bin',
        });
      });

      test('removes shorebird from Path and deletes directory', () async {
        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(
          () => shorebirdProcess.run(
            'powershell.exe',
            [
              '-Command',
              r'[Environment]::SetEnvironmentVariable("Path", "C:\Windows\System32;C:\Flutter\bin", "User")',
            ],
          ),
        ).called(1);

        verify(
          () => shorebirdProcess.start(
            'powershell.exe',
            [
              '-Command',
              // Splitting string causes adjacent string lints
              // ignore: lines_longer_than_80_chars
              'Start-Sleep -Seconds 1; Remove-Item -Recurse -Force "${shorebirdRoot.path}"',
            ],
            mode: ProcessStartMode.detached,
          ),
        ).called(1);

        verify(
          () => progress.complete('Shorebird has been uninstalled.'),
        ).called(1);
      });
    });

    group('mac/linux', () {
      setUp(() {
        when(() => platform.isWindows).thenReturn(false);
      });

      test('removes shorebird from rc files and deletes directory', () async {
        final bashrc = File(p.join(homeDirectory.path, '.bashrc'))
          ..createSync()
          ..writeAsStringSync(
            'export PATH="\$PATH:/some/path"\nexport PATH="\$PATH:~/.shorebird/bin"\n',
          );

        final zshrc = File(p.join(homeDirectory.path, '.zshrc'))
          ..createSync()
          ..writeAsStringSync(
            r'export PATH="$PATH:/some/path"',
          ); // No shorebird in here

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));

        expect(
          bashrc.readAsStringSync(),
          'export PATH="\$PATH:/some/path"\n',
        );
        expect(
          zshrc.readAsStringSync(),
          r'export PATH="$PATH:/some/path"',
        ); // Unchanged

        expect(shorebirdRoot.existsSync(), isFalse);

        verify(
          () => progress.complete('Shorebird has been uninstalled.'),
        ).called(1);
      });
    });
  });
}

import 'dart:convert';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/devicectl/apple_device.dart';
import 'package:shorebird_cli/src/executables/idevicesyslog.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(IDeviceSysLog, () {
    const deviceUdid = '12345678-1234567890ABCDEF';

    late AppleDevice device;
    late Directory flutterDirectory;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess process;
    late ShorebirdLogger logger;
    late Process loggerProcess;
    late String idevicesyslogPath;
    late IDeviceSysLog idevicesyslog;
    var stdoutOutput = '';
    var stderrOutput = '';

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          processRef.overrideWith(() => process),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      device = MockAppleDevice();
      flutterDirectory = Directory.systemTemp.createTempSync();
      process = MockShorebirdProcess();
      logger = MockShorebirdLogger();
      loggerProcess = MockProcess();
      shorebirdEnv = MockShorebirdEnv();
      idevicesyslog = IDeviceSysLog();

      when(() => device.udid).thenReturn(deviceUdid);
      when(() => device.isWired).thenReturn(true);
      when(
        () => process.start(
          any(),
          any(),
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async {
        return loggerProcess;
      });
      when(() => loggerProcess.stdout).thenAnswer(
        (_) => Stream.value(utf8.encode(stdoutOutput)),
      );
      when(() => loggerProcess.stderr).thenAnswer(
        (_) => Stream.value(utf8.encode(stderrOutput)),
      );
      when(() => loggerProcess.exitCode).thenAnswer((_) async => 0);

      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);

      idevicesyslogPath =
          runWithOverrides(() => IDeviceSysLog.idevicesyslogExecutable.path);
    });

    group('startLogger', () {
      late String expectedDyldLibraryPathString;

      setUp(() {
        expectedDyldLibraryPathString = IDeviceSysLog.deps
            .map(
              (dep) => p.join(
                shorebirdEnv.flutterDirectory.path,
                'bin',
                'cache',
                'artifacts',
                dep,
              ),
            )
            .join(':');
      });

      group('when device is wired', () {
        setUp(() {
          when(() => device.isWired).thenReturn(true);
        });

        test('runs idevicesyslog with the correct arguments', () async {
          await runWithOverrides(
            () => idevicesyslog.startLogger(device: device),
          );

          verify(
            () => process.start(
              idevicesyslogPath,
              ['-u', deviceUdid],
              environment: {'DYLD_LIBRARY_PATH': expectedDyldLibraryPathString},
            ),
          );
        });
      });

      group('when device is connected via network', () {
        setUp(() {
          when(() => device.isWired).thenReturn(false);
        });

        test('runs idevicesyslog with the correct arguments', () async {
          await runWithOverrides(
            () => idevicesyslog.startLogger(device: device),
          );

          verify(
            () => process.start(
              idevicesyslogPath,
              ['-u', deviceUdid, '--network'],
              environment: {'DYLD_LIBRARY_PATH': expectedDyldLibraryPathString},
            ),
          );
        });
      });

      test('logs stdout lines matching appLogLineRegex at info level',
          () async {
        stdoutOutput = '''
Nov  9 17:58:47 backboardd(QuartzCore)[51460] <Error>: IQCollectable client message err=0x10000004 : (ipc/send) timed out
Nov 10 14:46:57 Runner(Flutter)[1044] <Notice>: flutter: hello from stdout
Nov 10 17:58:47 kernel(Sandbox)[0] <Error>: Sandbox: Runner(52662) deny(1) iokit-get-properties iokit-class:AGXAcceleratorG14P property:CFBundleIdentifier
''';
        stderrOutput = '''
Nov  9 17:58:47 backboardd(QuartzCore)[51460] <Error>: IQCollectable client message err=0x10000004 : (ipc/send) timed out
Nov 10 14:46:57 Runner(Flutter)[1044] <Notice>: flutter: hello from stderr
Nov 10 17:58:47 kernel(Sandbox)[0] <Error>: Sandbox: Runner(52662) deny(1) iokit-get-properties iokit-class:AGXAcceleratorG14P property:CFBundleIdentifier
''';
        await runWithOverrides(
          () => idevicesyslog.startLogger(device: device),
        );

        verify(() => logger.info('flutter: hello from stdout')).called(1);
        verify(() => logger.info('flutter: hello from stderr')).called(1);
      });
    });
  });
}

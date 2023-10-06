import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(Devicectl, () {
    final fixturesPath = p.join('test', 'fixtures', 'devicectl');

    const deviceId = 'DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF';

    late ExitCode exitCode;
    late String jsonOutput;

    late ShorebirdProcess process;
    late ShorebirdProcessResult processResult;
    late Devicectl devicectl;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          processRef.overrideWith(() => process),
        },
      );
    }

    setUp(() {
      process = MockShorebirdProcess();
      processResult = MockShorebirdProcessResult();
      devicectl = Devicectl();

      when(() => process.run(any(), any())).thenAnswer((invocation) async {
        final processRunArgs =
            invocation.positionalArguments.last as List<String>;
        final jsonFilePath = processRunArgs.last;
        if (jsonFilePath.endsWith('.json')) {
          File(jsonFilePath)
            ..createSync()
            ..writeAsStringSync(jsonOutput);
        }
        return processResult;
      });
      when(() => processResult.exitCode).thenAnswer((_) => exitCode.code);
    });

    group('shouldUseDevicectl', () {
      test('returns false if devicectl is not available', () async {
        exitCode = ExitCode.software;
        expect(
          await runWithOverrides(() => devicectl.shouldUseDevicectl()),
          isFalse,
        );
      });

      test(
          'returns false if no CoreDevice with the given deviceID can be found',
          () async {
        exitCode = ExitCode.success;
        jsonOutput =
            File('$fixturesPath/device_list_success.json').readAsStringSync();
        expect(
          await runWithOverrides(
            () => devicectl.shouldUseDevicectl(deviceId: 'fake device id'),
          ),
          isFalse,
        );
      });

      test('returns false if no CoreDevice can be found', () async {
        exitCode = ExitCode.success;
        jsonOutput = File('$fixturesPath/device_list_success_empty.json')
            .readAsStringSync();
        expect(
          await runWithOverrides(() => devicectl.shouldUseDevicectl()),
          isFalse,
        );
      });

      test('returns false if device does not provide OS version', () async {
        exitCode = ExitCode.success;
        jsonOutput =
            File('$fixturesPath/device_list_success_no_os_version.json')
                .readAsStringSync();
        expect(
          await runWithOverrides(() => devicectl.shouldUseDevicectl()),
          isFalse,
        );
      });

      test("returns false if device's OS version is less than 17", () async {
        exitCode = ExitCode.success;
        jsonOutput = File('$fixturesPath/device_list_success_ios_15.json')
            .readAsStringSync();
        expect(
          await runWithOverrides(() => devicectl.shouldUseDevicectl()),
          isFalse,
        );
      });

      test("returns true if device's OS version is 17 or greater", () async {
        exitCode = ExitCode.success;
        jsonOutput =
            File('$fixturesPath/device_list_success.json').readAsStringSync();
        expect(
          await runWithOverrides(() => devicectl.shouldUseDevicectl()),
          isTrue,
        );
      });
    });

    group('installApp', () {
      late Directory runnerApp;

      setUp(() {
        jsonOutput = '';
        runnerApp = Directory.systemTemp.createTempSync();
      });

      group('when no json output file is found', () {
        setUp(() {
          when(() => process.run(any(), any()))
              .thenAnswer((invocation) async => processResult);
        });

        group('when the command returns a non-zero exit code', () {
          setUp(() {
            exitCode = ExitCode.cantCreate;
          });

          test('throws a DevicectlException with underlying ProcessException',
              () {
            expect(
              runWithOverrides(
                () => devicectl.installApp(
                  runnerApp: runnerApp,
                  deviceId: deviceId,
                ),
              ),
              throwsA(
                isA<DevicectlException>().having(
                  (e) => e.underlyingException,
                  'underlyingException',
                  isA<ProcessException>(),
                ),
              ),
            );
          });
        });

        group('when the command returns a zero exit code', () {
          setUp(() {
            exitCode = ExitCode.success;
          });

          test('throws Exception', () {
            expect(
              runWithOverrides(
                () => devicectl.installApp(
                  runnerApp: runnerApp,
                  deviceId: deviceId,
                ),
              ),
              throwsA(
                isA<Exception>().having(
                  (e) => '$e',
                  'message',
                  contains('Unable to find devicectl json output file'),
                ),
              ),
            );
          });
        });
      });

      group('when json file fails to parse', () {
        setUp(() {
          exitCode = ExitCode.success;
          jsonOutput = 'invalid json';
        });

        test('throws DevicectlException', () async {
          expect(
            runWithOverrides(
              () => devicectl.installApp(
                runnerApp: runnerApp,
                deviceId: deviceId,
              ),
            ),
            throwsA(
              isA<DevicectlException>()
                  .having((e) => e.message, 'message', 'App install failed')
                  .having(
                    (e) => e.underlyingException,
                    'underlyingException',
                    isA<FormatException>(),
                  ),
            ),
          );
        });
      });

      group('when install succeeds', () {
        setUp(() {
          exitCode = ExitCode.success;
          jsonOutput =
              File('$fixturesPath/install_success.json').readAsStringSync();
        });

        group('when output json does not contain app bundleId', () {
          setUp(() {
            jsonOutput = File('$fixturesPath/install_success_no_bundle_id.json')
                .readAsStringSync();
          });

          test('throws DevicectlException', () {
            expect(
              runWithOverrides(
                () => devicectl.installApp(
                  runnerApp: runnerApp,
                  deviceId: deviceId,
                ),
              ),
              throwsA(
                isA<DevicectlException>().having(
                  (e) => '${e.underlyingException}',
                  'underlyingException',
                  '''Exception: Unable to find installed app bundleID in devicectl output''',
                ),
              ),
            );
          });
        });

        group('when output json contains app bundleId', () {
          test("returns installed app's bundleId", () async {
            final bundleId = await runWithOverrides(
              () => devicectl.installApp(
                runnerApp: runnerApp,
                deviceId: deviceId,
              ),
            );
            expect(bundleId, 'dev.shorebird.ios-test');
          });
        });
      });
    });

    group('launchApp', () {
      const bundleId = 'com.example.app';

      group('when json contains error', () {
        setUp(() {
          exitCode = ExitCode.success;
          jsonOutput =
              File('$fixturesPath/launch_failure.json').readAsStringSync();
        });

        test(
            '''throws a DevicectlException with the underlying NSError message''',
            () async {
          expect(
            runWithOverrides(
              () => devicectl.launchApp(
                deviceId: deviceId,
                bundleId: bundleId,
              ),
            ),
            throwsA(
              isA<DevicectlException>().having(
                (e) => '${e.underlyingException}',
                'underlyingException',
                '''Exception: Unable to launch dev.shorebird.ios-test because the device was not, or could not be, unlocked.''',
              ),
            ),
          );
        });
      });

      group('when launch succeeds', () {
        setUp(() {
          exitCode = ExitCode.success;
          jsonOutput =
              File('$fixturesPath/launch_success.json').readAsStringSync();
        });

        test('completes successfully', () async {
          expect(
            runWithOverrides(
              () => devicectl.launchApp(
                deviceId: deviceId,
                bundleId: bundleId,
              ),
            ),
            completes,
          );
        });
      });
    });

    group('installAndLaunchApp', () {
      late Logger logger;
      late Progress progress;

      late String deviceListJsonOutput;
      late String installJsonOutput;
      late String launchJsonOutput;

      R runWithOverrides<R>(R Function() body) {
        return runScoped(
          body,
          values: {
            loggerRef.overrideWith(() => logger),
            processRef.overrideWith(() => process),
          },
        );
      }

      setUp(() {
        logger = MockLogger();
        progress = MockProgress();

        when(() => logger.progress(any())).thenReturn(progress);
        when(() => process.run(any(), any(that: contains('list'))))
            .thenAnswer((invocation) async {
          final processRunArgs =
              invocation.positionalArguments.last as List<String>;
          final jsonFilePath = processRunArgs.last;
          if (jsonFilePath.endsWith('.json')) {
            File(jsonFilePath)
              ..createSync()
              ..writeAsStringSync(deviceListJsonOutput);
          }
          return processResult;
        });
        when(() => process.run(any(), any(that: contains('install'))))
            .thenAnswer((invocation) async {
          final processRunArgs =
              invocation.positionalArguments.last as List<String>;
          final jsonFilePath = processRunArgs.last;
          if (jsonFilePath.endsWith('.json')) {
            File(jsonFilePath)
              ..createSync()
              ..writeAsStringSync(installJsonOutput);
          }
          return processResult;
        });
        when(() => process.run(any(), any(that: contains('launch'))))
            .thenAnswer((invocation) async {
          final processRunArgs =
              invocation.positionalArguments.last as List<String>;
          final jsonFilePath = processRunArgs.last;
          if (jsonFilePath.endsWith('.json')) {
            File(jsonFilePath)
              ..createSync()
              ..writeAsStringSync(launchJsonOutput);
          }
          return processResult;
        });
      });

      group('when no device is found', () {
        setUp(() {
          deviceListJsonOutput = File(
            '$fixturesPath/device_list_success_empty.json',
          ).readAsStringSync();
        });

        test('returns exit code 70', () async {
          expect(
            await runWithOverrides(
              () => devicectl.installAndLaunchApp(
                runnerAppDirectory: Directory.systemTemp.createTempSync(),
                deviceId: deviceId,
              ),
            ),
            equals(ExitCode.software.code),
          );
        });
      });

      group('when install fails', () {
        setUp(() {
          deviceListJsonOutput = File(
            '$fixturesPath/device_list_success.json',
          ).readAsStringSync();
          installJsonOutput =
              File('$fixturesPath/install_failure.json').readAsStringSync();
        });

        test('returns exit code 70 ', () async {
          expect(
            await runWithOverrides(
              () => devicectl.installAndLaunchApp(
                runnerAppDirectory: Directory.systemTemp.createTempSync(),
                deviceId: deviceId,
              ),
            ),
            equals(ExitCode.software.code),
          );
        });
      });

      group('when launch fails', () {
        setUp(() {
          deviceListJsonOutput = File(
            '$fixturesPath/device_list_success.json',
          ).readAsStringSync();
          installJsonOutput =
              File('$fixturesPath/install_success.json').readAsStringSync();
          launchJsonOutput =
              File('$fixturesPath/launch_failure.json').readAsStringSync();
        });

        test('returns exit code 70 ', () async {
          expect(
            await runWithOverrides(
              () => devicectl.installAndLaunchApp(
                runnerAppDirectory: Directory.systemTemp.createTempSync(),
                deviceId: deviceId,
              ),
            ),
            equals(ExitCode.software.code),
          );
        });
      });

      group('when install and launch succeed', () {
        setUp(() {
          deviceListJsonOutput = File(
            '$fixturesPath/device_list_success.json',
          ).readAsStringSync();
          installJsonOutput =
              File('$fixturesPath/install_success.json').readAsStringSync();
          launchJsonOutput =
              File('$fixturesPath/launch_success.json').readAsStringSync();
        });

        test('returns exit code 0', () async {
          expect(
            await runWithOverrides(
              () => devicectl.installAndLaunchApp(
                runnerAppDirectory: Directory.systemTemp.createTempSync(),
                deviceId: deviceId,
              ),
            ),
            equals(ExitCode.success.code),
          );
        });
      });
    });

    group('listAvailableIosDevices', () {
      setUp(() {
        exitCode = ExitCode.success;
      });

      group('when command fails', () {
        setUp(() {
          // This fixture is synthetic, as I was not able to get this command
          // to fail.
          jsonOutput =
              File('$fixturesPath/device_list_failure.json').readAsStringSync();
        });

        test('throws a DevicectlException', () {
          expect(
            runWithOverrides(devicectl.listAvailableIosDevices),
            throwsA(
              isA<DevicectlException>().having(
                (e) => e.message,
                'message',
                'Failed to list devices',
              ),
            ),
          );
        });
      });

      group('when command outputs incomplete json', () {
        setUp(() {
          // This fixture is synthetic, as I was not able to get this command
          // to fail.
          jsonOutput = File('$fixturesPath/device_list_success_no_devices.json')
              .readAsStringSync();
        });

        test('throws a DevicectlException', () {
          expect(
            runWithOverrides(devicectl.listAvailableIosDevices),
            throwsA(
              isA<DevicectlException>().having(
                (e) => e.message,
                'message',
                'Failed to list devices',
              ),
            ),
          );
        });
      });

      group('when command succeeds', () {
        setUp(() {
          jsonOutput =
              File('$fixturesPath/device_list_success.json').readAsStringSync();
        });

        test('returns a list of iOS devices', () async {
          final devices =
              await runWithOverrides(devicectl.listAvailableIosDevices);
          expect(devices, hasLength(1));
          final device = devices.first;
          expect(device.name, equals('Bryan Oltman’s iPhone'));
          expect(
            device.identifier,
            equals('DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF'),
          );
          expect(device.osVersionString, equals('17.0.2'));
          expect(device.platform, equals('iOS'));
        });
      });
    });
  });
}

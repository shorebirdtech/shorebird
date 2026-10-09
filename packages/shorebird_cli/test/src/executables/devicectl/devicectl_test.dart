import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/devicectl/apple_device.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(Devicectl, () {
    final fixturesPath = p.join('test', 'fixtures', 'devicectl');

    const deviceId = 'DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF';

    late ExitCode exitCode;
    late String jsonOutput;

    late AppleDevice device;
    late ShorebirdProcess process;
    late ShorebirdProcessResult processResult;
    late Devicectl devicectl;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          idevicesyslogRef.overrideWith(() => idevicesyslog),
          processRef.overrideWith(() => process),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(
        const AppleDevice(
          deviceProperties: DeviceProperties(name: 'iPhone 12'),
          hardwareProperties: HardwareProperties(
            platform: 'iOS',
            udid: '12345678-1234567890ABCDEF',
          ),
          connectionProperties: ConnectionProperties(
            transportType: 'wired',
            tunnelState: 'disconnected',
          ),
        ),
      );
    });

    setUp(() {
      device = MockAppleDevice();
      process = MockShorebirdProcess();
      processResult = MockShorebirdProcessResult();
      devicectl = Devicectl();

      when(() => device.udid).thenReturn(deviceId);

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

    group('deviceForLaunch', () {
      test('returns null if devicectl is not available', () async {
        exitCode = ExitCode.software;
        expect(
          await runWithOverrides(() => devicectl.deviceForLaunch()),
          isNull,
        );
      });

      test('returns null if devicectl availability check throws', () async {
        exitCode = ExitCode.software;
        when(() => process.run(any(), any())).thenThrow(Exception('oops'));
        await expectLater(
          await runWithOverrides(() => devicectl.deviceForLaunch()),
          isNull,
        );
      });

      test(
        'returns null if no CoreDevice with the given deviceID can be found',
        () async {
          exitCode = ExitCode.success;
          jsonOutput = File(
            '$fixturesPath/device_list_success.json',
          ).readAsStringSync();
          expect(
            await runWithOverrides(
              () => devicectl.deviceForLaunch(deviceId: 'fake device id'),
            ),
            isNull,
          );
        },
      );

      test('returns null if no CoreDevice can be found', () async {
        exitCode = ExitCode.success;
        jsonOutput = File(
          '$fixturesPath/device_list_success_empty.json',
        ).readAsStringSync();
        expect(
          await runWithOverrides(() => devicectl.deviceForLaunch()),
          isNull,
        );
      });

      test(
        "returns a device if device's OS version is 17 or greater",
        () async {
          exitCode = ExitCode.success;
          jsonOutput = File(
            '$fixturesPath/device_list_success.json',
          ).readAsStringSync();
          expect(
            await runWithOverrides(() => devicectl.deviceForLaunch()),
            isNotNull,
          );
        },
      );
    });

    group('installApp', () {
      late Directory runnerApp;

      setUp(() {
        jsonOutput = '';
        runnerApp = Directory.systemTemp.createTempSync();
      });

      group('when no json output file is found', () {
        setUp(() {
          when(
            () => process.run(any(), any()),
          ).thenAnswer((invocation) async => processResult);
        });

        group('when the command returns a non-zero exit code', () {
          setUp(() {
            exitCode = ExitCode.cantCreate;
          });

          test(
            'throws a DevicectlException with underlying ProcessException',
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
            },
          );
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
          jsonOutput = File(
            '$fixturesPath/install_success.json',
          ).readAsStringSync();
        });

        group('when output json does not contain app bundleId', () {
          setUp(() {
            jsonOutput = File(
              '$fixturesPath/install_success_no_bundle_id.json',
            ).readAsStringSync();
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
          jsonOutput = File(
            '$fixturesPath/launch_failure.json',
          ).readAsStringSync();
        });

        test(
          '''throws a DevicectlException with the underlying NSError message''',
          () async {
            expect(
              runWithOverrides(
                () =>
                    devicectl.launchApp(deviceId: deviceId, bundleId: bundleId),
              ),
              throwsA(
                isA<DevicectlException>().having(
                  (e) => '${e.underlyingException}',
                  'underlyingException',
                  '''Exception: Unable to launch dev.shorebird.ios-test because the device was not, or could not be, unlocked.''',
                ),
              ),
            );
          },
        );
      });

      group('when launch succeeds', () {
        setUp(() {
          exitCode = ExitCode.success;
          jsonOutput = File(
            '$fixturesPath/launch_success.json',
          ).readAsStringSync();
        });

        test('completes successfully', () async {
          expect(
            runWithOverrides(
              () => devicectl.launchApp(deviceId: deviceId, bundleId: bundleId),
            ),
            completes,
          );
        });
      });
    });

    group('installAndLaunchApp', () {
      late IDeviceSysLog idevicesyslog;
      late ShorebirdLogger logger;
      late Progress progress;
      late XcodeBuild xcodeBuild;

      late String deviceListJsonOutput;
      late String installJsonOutput;
      late String launchJsonOutput;

      R runWithOverrides<R>(R Function() body) {
        return runScoped(
          body,
          values: {
            idevicesyslogRef.overrideWith(() => idevicesyslog),
            loggerRef.overrideWith(() => logger),
            processRef.overrideWith(() => process),
            xcodeBuildRef.overrideWith(() => xcodeBuild),
          },
        );
      }

      setUp(() {
        idevicesyslog = MockIDeviceSysLog();
        logger = MockShorebirdLogger();
        progress = MockProgress();
        xcodeBuild = MockXcodeBuild();

        // Xcode versions before 26 read logs from idevicesyslog.
        when(
          () => xcodeBuild.version(),
        ).thenAnswer((_) async => 'Xcode 25.0 Build version 25A123');

        when(
          () => idevicesyslog.startLogger(device: any(named: 'device')),
        ).thenAnswer((_) async => ExitCode.success.code);
        when(() => logger.progress(any())).thenReturn(progress);
        when(() => process.run(any(), any(that: contains('list')))).thenAnswer((
          invocation,
        ) async {
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
        when(
          () => process.run(any(), any(that: contains('install'))),
        ).thenAnswer((invocation) async {
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
        when(
          () => process.run(any(), any(that: contains('launch'))),
        ).thenAnswer((invocation) async {
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
                device: device,
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
          installJsonOutput = File(
            '$fixturesPath/install_failure.json',
          ).readAsStringSync();
        });

        test('returns exit code 70 ', () async {
          expect(
            await runWithOverrides(
              () => devicectl.installAndLaunchApp(
                runnerAppDirectory: Directory.systemTemp.createTempSync(),
                device: device,
              ),
            ),
            equals(ExitCode.software.code),
          );

          verify(
            () => progress.fail(any(that: contains('Operation timed out'))),
          ).called(1);
        });
      });

      group('when launch fails', () {
        setUp(() {
          deviceListJsonOutput = File(
            '$fixturesPath/device_list_success.json',
          ).readAsStringSync();
          installJsonOutput = File(
            '$fixturesPath/install_success.json',
          ).readAsStringSync();
          launchJsonOutput = File(
            '$fixturesPath/launch_failure.json',
          ).readAsStringSync();
        });

        test('returns exit code 70 ', () async {
          expect(
            await runWithOverrides(
              () => devicectl.installAndLaunchApp(
                runnerAppDirectory: Directory.systemTemp.createTempSync(),
                device: device,
              ),
            ),
            equals(ExitCode.software.code),
          );

          verify(
            () => progress.fail(
              any(
                that: contains(
                  '''Unable to launch dev.shorebird.ios-test because the device was not, or could not be, unlocked.''',
                ),
              ),
            ),
          ).called(1);
        });
      });

      group('when install and launch succeed', () {
        setUp(() {
          deviceListJsonOutput = File(
            '$fixturesPath/device_list_success.json',
          ).readAsStringSync();
          installJsonOutput = File(
            '$fixturesPath/install_success.json',
          ).readAsStringSync();
          launchJsonOutput = File(
            '$fixturesPath/launch_success.json',
          ).readAsStringSync();
        });

        test('returns exit code 0', () async {
          expect(
            await runWithOverrides(
              () => devicectl.installAndLaunchApp(
                runnerAppDirectory: Directory.systemTemp.createTempSync(),
                device: device,
              ),
            ),
            equals(ExitCode.success.code),
          );
        });
      });
      group('when the Xcode version is 26 or later', () {
        late Process launchProcess;
        late List<String> launchOutputLines;
        late int launchExitCode;

        const expectedScriptArgs = [
          '-q',
          '-t',
          '0',
          '/dev/null',
          'xcrun',
          'devicectl',
          'device',
          'process',
          'launch',
          '--device',
          deviceId,
          '--console',
          '--environment-variables',
          '{"OS_ACTIVITY_DT_MODE":"enable"}',
          'dev.shorebird.ios-test',
        ];

        setUp(() {
          launchProcess = MockProcess();
          launchExitCode = 0;
          const prefix = '2026-10-08 20:06:42.768621-0700 Runner[1234:5678]';
          launchOutputLines = [
            'Launched application with dev.shorebird.ios-test bundle id.',
            'Waiting for the application to terminate…',
            '',
            '$prefix flutter: smoke: base',
            '$prefix [updater] [shorebird] Patch 1 is ready',
            '$prefix [UIKit App Config] some system noise',
          ];

          when(
            () => xcodeBuild.version(),
          ).thenAnswer((_) async => 'Xcode 27.0 Build version 27A266a');
          deviceListJsonOutput = File(
            '$fixturesPath/device_list_success.json',
          ).readAsStringSync();
          installJsonOutput = File(
            '$fixturesPath/install_success.json',
          ).readAsStringSync();
          launchJsonOutput = File(
            '$fixturesPath/launch_success.json',
          ).readAsStringSync();

          when(
            () => process.start('script', any()),
          ).thenAnswer((_) async => launchProcess);
          when(() => launchProcess.stdout).thenAnswer(
            (_) => Stream.value(
              utf8.encode(launchOutputLines.map((l) => '$l\r\n').join()),
            ),
          );
          when(
            () => launchProcess.stderr,
          ).thenAnswer((_) => const Stream.empty());
          when(
            () => launchProcess.exitCode,
          ).thenAnswer((_) async => launchExitCode);
        });

        test('launches with devicectl --console and logs app output', () async {
          expect(
            await runWithOverrides(
              () => devicectl.installAndLaunchApp(
                runnerAppDirectory: Directory.systemTemp.createTempSync(),
                device: device,
              ),
            ),
            equals(ExitCode.success.code),
          );

          verify(() => process.start('script', expectedScriptArgs)).called(1);
          verifyNever(
            () => idevicesyslog.startLogger(device: any(named: 'device')),
          );
          verifyNever(
            () => process.run(any(), any(that: contains('launch'))),
          );
          verify(() => logger.info('flutter: smoke: base')).called(1);
          verify(
            () => logger.info('[updater] [shorebird] Patch 1 is ready'),
          ).called(1);
          verifyNever(
            () => logger.info(any(that: contains('UIKit App Config'))),
          );
          verifyNever(() => logger.info(any(that: contains('Launched'))));
          verify(() => progress.complete()).called(2);
        });

        group('when devicectl never prints its attach line', () {
          setUp(() {
            const prefix = '2026-10-08 20:06:42.768621-0700 Runner[1234:5678]';
            launchOutputLines = [
              'Launched application with dev.shorebird.ios-test bundle id.',
              '$prefix flutter: smoke: base',
            ];
          });

          test('treats app output as attached and logs it', () async {
            expect(
              await runWithOverrides(
                () => devicectl.installAndLaunchApp(
                  runnerAppDirectory: Directory.systemTemp.createTempSync(),
                  device: device,
                ),
              ),
              equals(ExitCode.success.code),
            );

            verify(() => logger.info('flutter: smoke: base')).called(1);
            verifyNever(
              () => process.run(any(), any(that: contains('launch'))),
            );
            verifyNever(() => logger.warn(any()));
          });
        });

        group('when the console never attaches', () {
          setUp(() {
            launchExitCode = 1;
            launchOutputLines = [
              'ERROR: The application failed to launch.',
            ];
          });

          test('falls back to launching without logs', () async {
            expect(
              await runWithOverrides(
                () => devicectl.installAndLaunchApp(
                  runnerAppDirectory: Directory.systemTemp.createTempSync(),
                  device: device,
                ),
              ),
              equals(ExitCode.success.code),
            );

            verify(
              () => progress.fail(
                any(
                  that: allOf(
                    contains('devicectl exited with code 1'),
                    contains('The application failed to launch.'),
                  ),
                ),
              ),
            ).called(1);
            verify(
              () => logger.warn(
                any(that: contains('Launching the app without them')),
              ),
            ).called(1);
            verify(
              () => process.run(any(), any(that: contains('launch'))),
            ).called(1);
            verifyNever(
              () => idevicesyslog.startLogger(device: any(named: 'device')),
            );
          });

          group('and the fallback launch fails too', () {
            setUp(() {
              launchJsonOutput = File(
                '$fixturesPath/launch_failure.json',
              ).readAsStringSync();
            });

            test("reports devicectl's launch error", () async {
              expect(
                await runWithOverrides(
                  () => devicectl.installAndLaunchApp(
                    runnerAppDirectory: Directory.systemTemp.createTempSync(),
                    device: device,
                  ),
                ),
                equals(ExitCode.software.code),
              );

              verify(
                () => progress.fail(
                  any(that: contains('could not be, unlocked')),
                ),
              ).called(1);
            });
          });
        });

        group('when the launch process cannot be started', () {
          setUp(() {
            when(
              () => process.start('script', any()),
            ).thenThrow(const ProcessException('script', []));
          });

          test('falls back to launching without logs', () async {
            expect(
              await runWithOverrides(
                () => devicectl.installAndLaunchApp(
                  runnerAppDirectory: Directory.systemTemp.createTempSync(),
                  device: device,
                ),
              ),
              equals(ExitCode.success.code),
            );

            verify(
              () => progress.fail(
                any(that: contains('Unable to start devicectl')),
              ),
            ).called(1);
            verify(
              () => process.run(any(), any(that: contains('launch'))),
            ).called(1);
          });
        });
      });

      group('when the Xcode version cannot be determined', () {
        late Process launchProcess;

        setUp(() {
          launchProcess = MockProcess();
          when(
            () => xcodeBuild.version(),
          ).thenThrow(const ProcessException('xcodebuild', ['-version']));
          deviceListJsonOutput = File(
            '$fixturesPath/device_list_success.json',
          ).readAsStringSync();
          installJsonOutput = File(
            '$fixturesPath/install_success.json',
          ).readAsStringSync();
          when(
            () => process.start('script', any()),
          ).thenAnswer((_) async => launchProcess);
          when(() => launchProcess.stdout).thenAnswer(
            (_) => Stream.value(
              utf8.encode('Waiting for the application to terminate…\n'),
            ),
          );
          when(
            () => launchProcess.stderr,
          ).thenAnswer((_) => const Stream.empty());
          when(() => launchProcess.exitCode).thenAnswer((_) async => 0);
        });

        test('uses devicectl --console', () async {
          expect(
            await runWithOverrides(
              () => devicectl.installAndLaunchApp(
                runnerAppDirectory: Directory.systemTemp.createTempSync(),
                device: device,
              ),
            ),
            equals(ExitCode.success.code),
          );

          verify(() => process.start('script', any())).called(1);
          verifyNever(
            () => idevicesyslog.startLogger(device: any(named: 'device')),
          );
        });

        test(
          'uses devicectl --console when the version is unrecognized',
          () async {
            when(
              () => xcodeBuild.version(),
            ).thenAnswer((_) async => 'unrecognized');
            expect(
              await runWithOverrides(
                () => devicectl.installAndLaunchApp(
                  runnerAppDirectory: Directory.systemTemp.createTempSync(),
                  device: device,
                ),
              ),
              equals(ExitCode.success.code),
            );

            verify(() => process.start('script', any())).called(1);
            verifyNever(
              () => idevicesyslog.startLogger(device: any(named: 'device')),
            );
          },
        );
      });

      group('when the Xcode version is before 26', () {
        setUp(() {
          deviceListJsonOutput = File(
            '$fixturesPath/device_list_success.json',
          ).readAsStringSync();
          installJsonOutput = File(
            '$fixturesPath/install_success.json',
          ).readAsStringSync();
          launchJsonOutput = File(
            '$fixturesPath/launch_success.json',
          ).readAsStringSync();
        });

        test('uses idevicesyslog', () async {
          await runWithOverrides(
            () => devicectl.installAndLaunchApp(
              runnerAppDirectory: Directory.systemTemp.createTempSync(),
              device: device,
            ),
          );

          verify(
            () => idevicesyslog.startLogger(device: device),
          ).called(1);
          verifyNever(() => process.start('script', any()));
        });
      });
    });

    group('parseConsoleLine', () {
      test('returns lines without os_log metadata unchanged', () {
        expect(
          Devicectl.parseConsoleLine('hello from stdout'),
          equals('hello from stdout'),
        );
      });

      test('strips metadata from Dart print output', () {
        expect(
          Devicectl.parseConsoleLine(
            '2026-10-08 20:06:42.768621-0700 Runner[1234:5678] flutter: hi',
          ),
          equals('flutter: hi'),
        );
      });

      test('strips metadata from Shorebird logs', () {
        expect(
          Devicectl.parseConsoleLine(
            '2026-10-08 20:06:42.768621-0700 Runner[1234:5678] '
            '[updater::cache] [shorebird] No patch available',
          ),
          equals('[updater::cache] [shorebird] No patch available'),
        );
      });

      test('strips metadata from Flutter engine logs', () {
        expect(
          Devicectl.parseConsoleLine(
            '2026-10-08 20:06:42.768621-0700 Runner[1234:5678] '
            '[ERROR:flutter/shell/common/shell.cc(1)] oops',
          ),
          equals('[ERROR:flutter/shell/common/shell.cc(1)] oops'),
        );
      });

      test('handles app names with spaces', () {
        expect(
          Devicectl.parseConsoleLine(
            '2026-10-08 20:06:42.768621-0700 My App[1234:5678] flutter: hi',
          ),
          equals('flutter: hi'),
        );
      });

      test('handles leading terminal control characters', () {
        expect(
          Devicectl.parseConsoleLine(
            '\x04\b\b2026-10-08 20:06:42.768621-0700 Runner[1:2] flutter: hi',
          ),
          equals('flutter: hi'),
        );
      });

      test('returns null for other os_log messages', () {
        expect(
          Devicectl.parseConsoleLine(
            '2026-10-08 20:06:42.768621-0700 Runner[1234:5678] '
            'CoreText note: something',
          ),
          isNull,
        );
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
          jsonOutput = File(
            '$fixturesPath/device_list_failure.json',
          ).readAsStringSync();
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
          jsonOutput = File(
            '$fixturesPath/device_list_success_no_devices.json',
          ).readAsStringSync();
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
          jsonOutput = File(
            '$fixturesPath/device_list_success.json',
          ).readAsStringSync();
        });

        test('returns a list of iOS devices', () async {
          final devices = await runWithOverrides(
            devicectl.listAvailableIosDevices,
          );
          expect(devices, hasLength(1));
          final outputDevice = devices.first;
          expect(outputDevice.name, equals('Bryan Oltman’s iPhone'));
          expect(outputDevice.udid, equals('11111111-1111111111111111'));
          expect(outputDevice.osVersionString, equals('17.0.2'));
          expect(outputDevice.platform, equals('iOS'));
        });
      });

      group('when command succeeds with some unavailable devices', () {
        setUp(() {
          jsonOutput = File(
            '$fixturesPath/device_list_partial_success.json',
          ).readAsStringSync();
        });

        test('returns a list of iOS devices', () async {
          final devices = await runWithOverrides(
            devicectl.listAvailableIosDevices,
          );
          expect(devices, hasLength(2));
          final firstDevice = devices[0];
          expect(firstDevice.name, equals('Test'));
          expect(firstDevice.udid, equals('11111111-1111111111111111'));
          expect(firstDevice.osVersionString, equals('18.5'));
          expect(firstDevice.platform, equals('iOS'));

          final secondDevice = devices[1];
          expect(secondDevice.name, equals('Test iPhone XS'));
          expect(secondDevice.udid, equals('22222222-2222222222222222'));
          expect(secondDevice.osVersionString, equals('18.5'));
          expect(secondDevice.platform, equals('iOS'));
        });
      });

      group('when one of the devices is paired but unreachable', () {
        setUp(() {
          jsonOutput = File(
            '$fixturesPath/device_list_with_unreachable.json',
          ).readAsStringSync();
        });

        test('omits the unreachable device', () async {
          final devices = await runWithOverrides(
            devicectl.listAvailableIosDevices,
          );
          expect(devices, hasLength(1));
          expect(devices.first.name, equals('Reachable iPhone'));
          expect(
            devices.first.udid,
            equals('11111111-1111111111111111'),
          );
        });
      });
    });

    group('listAllIosDevices', () {
      setUp(() {
        exitCode = ExitCode.success;
      });

      group('when one of the devices is paired but unreachable', () {
        setUp(() {
          jsonOutput = File(
            '$fixturesPath/device_list_with_unreachable.json',
          ).readAsStringSync();
        });

        test(
          'returns the unreachable device alongside reachable ones',
          () async {
            final devices = await runWithOverrides(
              devicectl.listAllIosDevices,
            );
            expect(devices, hasLength(2));

            final reachable = devices.firstWhere((d) => d.isAvailable);
            expect(reachable.name, equals('Reachable iPhone'));
            expect(reachable.osVersionString, equals('18.5'));

            final unreachable = devices.firstWhere((d) => !d.isAvailable);
            expect(unreachable.name, equals('Unreachable iPhone'));
            expect(unreachable.osVersionString, equals('17.4.1'));
            expect(
              unreachable.udid,
              equals('22222222-2222222222222222'),
            );
          },
        );
      });

      group('when command fails', () {
        setUp(() {
          jsonOutput = File(
            '$fixturesPath/device_list_failure.json',
          ).readAsStringSync();
        });

        test('throws a DevicectlException', () {
          expect(
            runWithOverrides(devicectl.listAllIosDevices),
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
    });
  });
}

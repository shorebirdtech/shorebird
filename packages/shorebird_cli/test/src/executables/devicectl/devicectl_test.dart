import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group(Devicectl, () {
    final fixturesPath = p.join('test', 'fixtures', 'devicectl');

    const deviceId = 'test_device_id';

    late ExitCode exitCode;
    late String stdout;
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
        File(jsonFilePath)
          ..createSync()
          ..writeAsStringSync(jsonOutput);
        return processResult;
      });
      when(() => processResult.exitCode).thenAnswer((_) => exitCode.code);
      when(() => processResult.stdout).thenAnswer((_) => stdout);
    });

    group('installApp', () {
      late Directory runnerApp;

      setUp(() {
        jsonOutput = '';
        runnerApp = Directory.systemTemp.createTempSync();
      });

      group('when the command returns a non-zero exit code', () {
        setUp(() {
          exitCode = ExitCode.cantCreate;
          stdout = '';
        });

        test('throws a ProcessException', () {
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

        group('when no json output file is found', () {
          setUp(() {
            exitCode = ExitCode.success;
            stdout = '';

            when(() => process.run(any(), any()))
                .thenAnswer((invocation) async => processResult);
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
                  stringContainsInOrder(['Unable to find', 'output file']),
                ),
              ),
            );
          });
        });

        group('when json file fails to parse', () {
          setUp(() {
            exitCode = ExitCode.success;
            stdout = '';
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
      group('when the command returns a non-zero exit code', () {
        const bundleId = 'com.example.app';

        setUp(() {
          exitCode = ExitCode.cantCreate;
          stdout = '';
        });

        test('throws a ProcessException', () {
          expect(
            runWithOverrides(
              () => devicectl.launchApp(
                deviceId: deviceId,
                bundleId: bundleId,
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

        group('when json file fails to parse', () {
          setUp(() {
            exitCode = ExitCode.success;
            stdout = '';
          });

          test('throws DevicectlException', () async {
            when(() => process.run(any(), any()))
                .thenAnswer((invocation) async {
              final processRunArgs =
                  invocation.positionalArguments.last as List<String>;
              final jsonFilePath = processRunArgs.last;
              File(jsonFilePath)
                ..createSync()
                ..writeAsStringSync('invalid json');
              return processResult;
            });

            expect(
              runWithOverrides(
                () => devicectl.launchApp(
                  deviceId: deviceId,
                  bundleId: bundleId,
                ),
              ),
              throwsA(
                isA<DevicectlException>()
                    .having((e) => e.message, 'message', 'App launch failed')
                    .having(
                      (e) => e.underlyingException,
                      'underlyingException',
                      isA<FormatException>(),
                    ),
              ),
            );
          });
        });

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
    });

    group('listIosDevices', () {
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
            runWithOverrides(devicectl.listIosDevices),
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
          final devices = await runWithOverrides(devicectl.listIosDevices);
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

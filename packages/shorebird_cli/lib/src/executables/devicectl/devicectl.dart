import 'dart:convert';

import 'package:io/io.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/executables/devicectl/ios_device_info.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

typedef BundleId = String;

/// A reference to a [Devicectl] instance.
final devicectlRef = create(Devicectl.new);

/// The [Devicectl] instance available in the current zone.
Devicectl get devicectl => read(devicectlRef);

/// A wrapper around the `devicectl` command.
class Devicectl {
  static const executableName = 'xcrun';
  static const baseArgs = [
    'devicectl',
  ];

  Future<BundleId> installApp({
    required Directory runnerApp,
    required String deviceId,
  }) async {
    final args = [
      ...baseArgs,
      'device',
      'install',
      'app',
      '--device',
      deviceId,
      runnerApp.path,
    ];
    final jsonResult = await _runJsonCommand(args: args);
    // ignore: avoid_dynamic_calls
    return jsonResult['result']['installedApplications'][0]['bundleID']
        as String;
  }

  Future<void> launchApp({
    required String deviceId,
    required String bundleId,
  }) async {
    final args = [
      ...baseArgs,
      'device',
      'process',
      'launch',
      '--device',
      deviceId,
      bundleId,
    ];
    final jsonResult = await _runJsonCommand(args: args);
    print('result is');
    print(jsonResult);
    // TODO
  }

  Future<List<IosDeviceInfo>> listDevices() async {
    final args = [
      ...baseArgs,
      'list',
      'devices',
    ];
    final jsonResult = await _runJsonCommand(args: args);
    return (jsonResult['result']['devices'] as List)
        .whereType<Json>()
        .map(IosDeviceInfo.fromJson)
        .toList();
  }

  Future<IosDeviceInfo> deviceInfo({required String deviceId}) async {
    final args = [
      ...baseArgs,
      'device',
      'info',
      'details',
      '--device',
      deviceId,
    ];

    final jsonResult = await _runJsonCommand(args: args);
    return IosDeviceInfo.fromJson(jsonResult['result'] as Json);
  }

  Future<Json> _runJsonCommand({required List<String> args}) async {
    final tempDir = Directory.systemTemp.createTempSync();
    final jsonOutputFile = File(p.join(tempDir.path, 'info.json'));

    final result = await process.run(executableName, [
      ...args,
      '--json-output',
      jsonOutputFile.path,
    ]);
    if (result.exitCode != ExitCode.success.code) {
      throw ProcessException(executableName, args, '${result.stderr}');
    }

    if (!jsonOutputFile.existsSync()) {
      throw Exception(
        'Unable to find $executableName output file: ${jsonOutputFile.path}',
      );
    }

    final jsonString = jsonOutputFile.readAsStringSync();
    return jsonDecode(jsonString) as Json;
  }
}

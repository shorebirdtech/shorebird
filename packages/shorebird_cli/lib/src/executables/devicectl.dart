import 'package:io/io.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

/// A wrapper around the `devicectl` command.
class Devicectl {
  static const executableName = 'xcrun';
  static const baseArgs = [
    'devicectl',
    'device',
  ];

  Future<void> installApp({
    required Directory runnerApp,
    required String deviceId,
  }) async {
    final tempDir = Directory.systemTemp.createTempSync();
    final jsonOutputFile = File(p.join(tempDir.path, 'install.json'));
    final args = [
      ...baseArgs,
      'install',
      'app',
      '--device',
      deviceId,
      runnerApp.path,
      '--json-output',
      jsonOutputFile.path,
    ];

    final result = await process.run(executableName, args);
    if (result.exitCode != ExitCode.success.code) {
      throw ProcessException(executableName, args, '${result.stderr}');
    }
  }

  Future<void> launchApp({
    required String deviceId,
    required String bundleId,
  }) async {
    final tempDir = Directory.systemTemp.createTempSync();
    final jsonOutputFile = File(p.join(tempDir.path, 'launch.json'));
    final args = [
      ...baseArgs,
      'process',
      'launch',
      '--device',
      deviceId,
      bundleId,
      '--json-output',
      jsonOutputFile.path,
    ];

    final result = await process.run(executableName, args);
    if (result.exitCode != ExitCode.success.code) {
      throw ProcessException(executableName, args, '${result.stderr}');
    }
  }

  Future<Version> iosVersion({required String deviceId}) async {
    final tempDir = Directory.systemTemp.createTempSync();
    final jsonOutputFile = File(p.join(tempDir.path, 'info.json'));
    final args = [
      ...baseArgs,
      'info',
      'details',
      '--device',
      deviceId,
      '--json-output',
      jsonOutputFile.path,
    ];

    final result = await process.run(executableName, args);
    if (result.exitCode != ExitCode.success.code) {
      throw ProcessException(executableName, args, '${result.stderr}');
    }

    // TODO
    return Version.parse('');
  }
}

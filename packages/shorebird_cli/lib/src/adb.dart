import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/process.dart';

/// A wrapper around the `adb` command.
class Adb {
  Future<ShorebirdProcessResult> _exec(String command) async {
    final adbPath = androidSdk.adbPath;
    if (adbPath == null) throw Exception('Unable to locate adb.');

    return process.run(adbPath, command.split(' '));
  }

  /// Starts the app with the given [package] name.
  Future<void> startApp(String package) async {
    final result = await _exec('shell monkey -p $package 1');
    if (result.exitCode != 0) {
      throw Exception('Unable to start app: ${result.stderr}');
    }
  }
}

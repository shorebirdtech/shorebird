import 'dart:async';
import 'dart:io';

import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/process.dart';

/// A reference to a [Adb] instance.
final adbRef = create(Adb.new);

/// The [Adb] instance available in the current zone.
Adb get adb => read(adbRef);

/// A wrapper around the `adb` command.
class Adb {
  Future<ShorebirdProcessResult> _exec(String command) async {
    final adbPath = androidSdk.adbPath;
    if (adbPath == null) throw Exception('Unable to locate adb.');

    return process.run(adbPath, command.split(' '));
  }

  Future<Process> _stream(String command) async {
    final adbPath = androidSdk.adbPath;
    if (adbPath == null) throw Exception('Unable to locate adb.');

    return process.start(adbPath, command.split(' '));
  }

  /// Starts the app with the given [package] name.
  Future<void> startApp({
    required String package,
    String? deviceId,
  }) async {
    final args = [
      if (deviceId != null) '-s $deviceId',
      'shell',
      'monkey',
      '-p $package',
      '1',
    ];
    final result = await _exec(args.join(' '));
    if (result.exitCode != 0) {
      throw Exception('Unable to start app: ${result.stderr}');
    }
  }

  Future<Process> logcat({
    String? filter,
    String? deviceId,
  }) async {
    final args = [
      if (deviceId != null) '-s $deviceId',
      'logcat',
      if (filter != null) '-s $filter',
    ];
    return _stream(args.join(' '));
  }
}

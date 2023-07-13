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
  Future<void> startApp(String package) async {
    final result = await _exec('shell monkey -p $package 1');
    if (result.exitCode != 0) {
      throw Exception('Unable to start app: ${result.stderr}');
    }
  }

  Future<Process> logcat({String? filter}) async {
    final logcat = await _stream('logcat');
    if (filter == null) return logcat;
    final grep = await process.start('grep', [filter]);
    unawaited(logcat.stdout.pipe(grep.stdin));
    return grep;
  }
}

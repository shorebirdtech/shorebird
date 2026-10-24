import 'dart:async';
import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// A reference to a [Adb] instance.
final adbRef = create(Adb.new);

/// The [Adb] instance available in the current zone.
Adb get adb => read(adbRef);

/// A wrapper around the `adb` command.
class Adb {
  Future<ShorebirdProcessResult> _exec(List<String> args) async {
    final adbPath = androidSdk.adbPath;
    if (adbPath == null) throw Exception('Unable to locate adb.');

    return process.run(adbPath, args);
  }

  Future<Process> _stream(List<String> args) async {
    final adbPath = androidSdk.adbPath;
    if (adbPath == null) throw Exception('Unable to locate adb.');

    return process.start(adbPath, args);
  }

  /// Clears the app data for the given [package] name.
  Future<void> clearAppData({required String package, String? deviceId}) async {
    final args = [
      if (deviceId != null) ...['-s', deviceId],
      'shell',
      'pm',
      'clear',
      package,
    ];
    final result = await _exec(args);
    if (result.exitCode != 0) {
      throw Exception('Unable to clear app data: ${result.stderr}');
    }
  }

  /// Starts the app with the given [package] name.
  Future<void> startApp({required String package, String? deviceId}) async {
    final args = [
      if (deviceId != null) ...['-s', deviceId],
      'shell',
      'monkey',
      // Adjust percentage of "system" key events to 0.
      // This is needed to support Android systems with no hardware keys.
      ...['--pct-syskeys', '0'],
      ...['-p', package],
      '1',
    ];
    final result = await _exec(args);
    if (result.exitCode != 0) {
      throw Exception('Unable to start app: ${result.stderr}');
    }
  }

  /// Returns the timestamp of the newest entry in the device log, in the
  /// `MM-DD hh:mm:ss.mmm` form `adb logcat -T` accepts, or null if the log is
  /// empty.
  Future<String?> latestLogTimestamp({String? deviceId}) async {
    final args = [
      if (deviceId != null) ...['-s', deviceId],
      ...['logcat', '-d', '-t', '1', '-v', 'time'],
    ];
    final result = await _exec(args);
    if (result.exitCode != 0) {
      throw Exception('Unable to read the device log: ${result.stderr}');
    }
    final timestamp = RegExp(
      r'^\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}',
      multiLine: true,
    );
    return timestamp.allMatches('${result.stdout}').lastOrNull?.group(0);
  }

  /// Runs `adb logcat`, printing entries logged since [since] (a timestamp
  /// from [latestLogTimestamp]) and then following new ones. Without [since]
  /// it starts from the newest entry, so anything logged before it attaches is
  /// missed.
  Future<Process> logcat({
    String? filter,
    String? deviceId,
    String? since,
  }) async {
    final args = [
      if (deviceId != null) ...['-s', deviceId],
      'logcat',
      ...['-T', since ?? '1'],
      if (filter != null) ...['-s', filter],
    ];
    return _stream(args);
  }
}

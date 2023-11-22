import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/args.dart';
import 'package:shorebird_cli/src/executables/devicectl/apple_device.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// A reference to a [IDeviceSysLog] instance.
final idevicesyslogRef = create(IDeviceSysLog.new);

/// The [IDeviceSysLog] instance available in the current zone.
IDeviceSysLog get idevicesyslog => read(idevicesyslogRef);

/// {@template idevicesyslog}
/// A wrapper around the `idevicesyslog` executable.
/// {@endtemplate}
class IDeviceSysLog {
  /// The location of the libimobiledevice library, which contains
  /// idevicesyslog.
  static Directory get libimobiledeviceDirectory => Directory(
        p.join(
          shorebirdEnv.flutterDirectory.path,
          'bin',
          'cache',
          'artifacts',
          'libimobiledevice',
        ),
      );

  /// The location of the idevicesyslog executable.
  static File get idevicesyslogExecutable => File(
        p.join(libimobiledeviceDirectory.path, 'idevicesyslog'),
      );

  /// The libraries that idevicesyslog depends on.
  @visibleForTesting
  static const deps = [
    'libimobiledevice',
    'usbmuxd',
    'libplist',
    'openssl',
    'ios-deploy',
  ];

  /// idevicesyslog has Flutter-provided dependencies, so we need to tell the
  /// dynamic linker where to find them.
  String get _dyldPathEntry => deps
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

  /// idevicesyslog tails all logs produced by the device (similar to what is
  /// shown in Console.app). This is very noisy and we only want to show logs
  /// that are produced by the app. These log lines are of the form:
  ///   Nov 10 14:46:57 Runner(Flutter)[1044] <Notice>: flutter: hello
  static RegExp appLogLineRegex = RegExp(r'\(Flutter\)\[\d+\] <Notice>: (.*)$');

  /// Starts an instance of idevicesyslog for the given device ID. Returns the
  /// exit code of the process.
  ///
  /// stdout and stderr are parsed for lines matching [appLogLineRegex], and
  /// those lines are logged at an info level.
  Future<int> startLogger({required AppleDevice device}) async {
    logger.detail(
      'launching idevicesyslog with DYLD_LIBRARY_PATH=$_dyldPathEntry',
    );

    final loggerProcess = await process.start(
      idevicesyslogExecutable.path,
      [
        '-u',
        device.udid,
        // If the device is not connected via USB, we need to specify the
        // network flag.
        if (!device.isWired) '--${ArgsKey.network}',
      ],
      environment: {
        'DYLD_LIBRARY_PATH': _dyldPathEntry,
      },
    );

    loggerProcess.stdout
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen(_parseLogLine);
    loggerProcess.stderr
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen(_parseLogLine);
    return loggerProcess.exitCode;
  }

  void _parseLogLine(String line) {
    final matches = appLogLineRegex.allMatches(line);
    if (matches.isNotEmpty) {
      logger.info(matches.first.group(1));
    }
  }
}

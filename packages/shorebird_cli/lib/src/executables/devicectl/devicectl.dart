import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:io/io.dart';
import 'package:json_path/json_path.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/devicectl/apple_device.dart';
import 'package:shorebird_cli/src/executables/devicectl/nserror.dart';
import 'package:shorebird_cli/src/executables/idevicesyslog.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Typedef for a bundle identifier string.
typedef BundleId = String;

/// {@template devicectl_exception}
/// Thrown when a [Devicectl] command fails.
/// {@endtemplate}
class DevicectlException implements Exception {
  /// {@macro devicectl_exception}
  DevicectlException({required this.message, this.underlyingException});

  /// A message describing this exception.
  final String message;

  /// The exception that caused this exception to be thrown, if any.
  final Object? underlyingException;

  @override
  String toString() =>
      '''
DevicectlException: $message
Underlying exception: ${underlyingException ?? '(none)'}
''';
}

/// A reference to a [Devicectl] instance.
final devicectlRef = create(Devicectl.new);

/// The [Devicectl] instance available in the current zone.
Devicectl get devicectl => read(devicectlRef);

/// A wrapper around the `devicectl` command.
class Devicectl {
  /// The executable name (`xcrun`).
  static const executableName = 'xcrun';

  /// The base arguments for the `devicectl` command.
  static const baseArgs = ['devicectl'];

  /// Whether the `devicectl` command is available.
  Future<bool> _isAvailable() async {
    try {
      final result = await process.run(executableName, [
        ...baseArgs,
        '--version',
      ]);
      return result.exitCode == ExitCode.success.code;
    } on Exception {
      return false;
    }
  }

  /// Returns the first available iOS device, or the device with the given
  /// [deviceId] if provided. Devices that are running iOS <17 are not
  /// "CoreDevice"s and are not visible to devicectl. Returns null if devicectl
  /// is not available or no devices are found.
  Future<AppleDevice?> deviceForLaunch({String? deviceId}) async {
    if (!await _isAvailable()) {
      return null;
    }

    final devices = await listAvailableIosDevices();

    if (deviceId != null) {
      return devices.firstWhereOrNull((d) => d.udid == deviceId);
    } else {
      return devices.firstOrNull;
    }
  }

  /// Installs the given [runnerApp] on the device with the given [deviceId].
  ///
  /// Returns the bundle ID of the installed app.
  Future<BundleId> installApp({
    required Directory runnerApp,
    required String deviceId,
  }) async {
    const failureErrorMessage = 'App install failed';

    final args = [
      ...baseArgs,
      'device',
      'install',
      'app',
      '--device',
      deviceId,
      runnerApp.path,
    ];
    final Json jsonResult;
    try {
      jsonResult = await _runJsonCommand(args: args);
    } catch (error) {
      throw DevicectlException(
        message: failureErrorMessage,
        underlyingException: error,
      );
    }

    final String bundleId;
    try {
      final maybeBundleId =
          JsonPath(
                r'$.result.installedApplications[0].bundleID',
              ).read(jsonResult).firstOrNull?.value
              as String?;
      if (maybeBundleId == null) {
        throw Exception(
          'Unable to find installed app bundleID in devicectl output',
        );
      }

      bundleId = maybeBundleId;
    } catch (error) {
      throw DevicectlException(
        message: failureErrorMessage,
        underlyingException: error,
      );
    }

    return bundleId;
  }

  /// Launches the app with the given [bundleId] on the device with the given
  /// [deviceId]. This will fail if the app is not already installed on the
  /// device. Use [installAndLaunchApp] to both install and launch the app.
  Future<void> launchApp({
    required String deviceId,
    required String bundleId,
  }) async {
    const failureErrorMessage = 'App launch failed';

    final args = [
      ...baseArgs,
      'device',
      'process',
      'launch',
      '--device',
      deviceId,
      bundleId,
    ];

    try {
      await _runJsonCommand(args: args);
    } catch (error) {
      throw DevicectlException(
        message: failureErrorMessage,
        underlyingException: error,
      );
    }
  }

  /// The first Xcode major version for which app logs are read from
  /// `devicectl device process launch --console` instead of idevicesyslog.
  ///
  /// This matches flutter_tools, which stopped using idevicesyslog for
  /// CoreDevices starting with Xcode 26.
  static const minimumConsoleLoggingXcodeVersion = 26;

  /// The line devicectl prints once the app has launched and its console is
  /// attached.
  static const consoleAttachedMarker =
      'Waiting for the application to terminate';

  /// Whether app logs should be read from devicectl's console rather than
  /// idevicesyslog, based on the installed Xcode version. If the version
  /// can't be determined, assumes a current Xcode.
  Future<bool> _useConsoleLogging() async {
    try {
      final version = await xcodeBuild.version();
      final major = RegExp(r'Xcode (\d+)').firstMatch(version)?.group(1);
      if (major == null) return true;
      return int.parse(major) >= minimumConsoleLoggingXcodeVersion;
    } on Exception catch (error) {
      logger.detail('Unable to determine Xcode version: $error');
      return true;
    }
  }

  /// Installs and launches the given [runnerAppDirectory] on [device]. [device]
  /// should be obtained using [listAvailableIosDevices]. After successfully
  /// launching the app, streams the app's logs until the app exits.
  ///
  /// With Xcode [minimumConsoleLoggingXcodeVersion] or later, logs come from
  /// the devicectl launch process (see [launchAppAndStreamConsole]). With
  /// older Xcode versions, logs come from idevicesyslog.
  Future<int> installAndLaunchApp({
    required Directory runnerAppDirectory,
    required AppleDevice device,
  }) async {
    final useConsoleLogging = await _useConsoleLogging();

    final installProgress = logger.progress('Installing app');

    // Start the logger before launching the app to ensure we capture all
    // logs. Starting the logger process after launching the app can result
    // in missing some shorebird logs.
    final loggerExitCodeFuture = useConsoleLogging
        ? null
        : idevicesyslog.startLogger(device: device);

    final String bundleId;
    try {
      bundleId = await installApp(
        deviceId: device.udid,
        runnerApp: runnerAppDirectory,
      );
    } on Exception catch (error) {
      installProgress.fail('Failed to install app: $error');
      return ExitCode.software.code;
    }
    installProgress.complete();

    if (useConsoleLogging) {
      final attached = await launchAppAndStreamConsole(
        deviceId: device.udid,
        bundleId: bundleId,
      );
      if (attached) return ExitCode.success.code;
      // Fall back to launching the app the way we did before reading logs
      // from the console, so a problem with log streaming never stops the
      // app from launching. If the launch itself is the problem, this
      // reports devicectl's error.
      logger.warn(
        "Unable to attach to the app's console, so its logs will not be "
        'shown. Launching the app without them.',
      );
    }

    final launchProgress = logger.progress('Launching app');
    try {
      await launchApp(deviceId: device.udid, bundleId: bundleId);
    } on Exception catch (error) {
      launchProgress.fail('Failed to launch app: $error');
      return ExitCode.software.code;
    }
    launchProgress.complete();

    if (loggerExitCodeFuture != null) {
      final loggerExitCode = await loggerExitCodeFuture;
      logger.detail('idevicesyslog exited with code $loggerExitCode');
    }

    return ExitCode.success.code;
  }

  /// Launches the app with the given [bundleId] on the device with the given
  /// [deviceId], stays attached to its console, and logs the app's output
  /// until the app exits.
  ///
  /// Returns whether devicectl attached to the app's console. Attachment is
  /// recognized by devicectl's [consoleAttachedMarker] line or by the first
  /// line of app output, so a change to devicectl's wording doesn't hide the
  /// app's logs. When this returns false, the app may not have launched and
  /// the caller should launch it another way.
  ///
  /// This mirrors how flutter_tools launches release builds on CoreDevices
  /// with Xcode 26+:
  ///   * `--console` connects the app's standard streams to devicectl's.
  ///   * `OS_ACTIVITY_DT_MODE=enable` makes the app mirror os_log and syslog
  ///     messages (which carry Dart `print` output and the Shorebird
  ///     updater's logs) to its stderr.
  ///   * devicectl runs under `script` so that it has a terminal attached
  ///     and forwards the app's output. `-q` keeps `script`'s own banner
  ///     lines out of the output.
  Future<bool> launchAppAndStreamConsole({
    required String deviceId,
    required String bundleId,
  }) async {
    final launchProgress = logger.progress('Launching app');

    final Process launchProcess;
    try {
      launchProcess = await process.start('script', [
        '-q',
        '-t',
        '0',
        '/dev/null',
        executableName,
        ...baseArgs,
        'device',
        'process',
        'launch',
        '--device',
        deviceId,
        '--console',
        '--environment-variables',
        jsonEncode({'OS_ACTIVITY_DT_MODE': 'enable'}),
        bundleId,
      ]);
    } on Exception catch (error) {
      launchProgress.fail('Unable to start devicectl: $error');
      return false;
    }

    var attached = false;
    final launchOutput = <String>[];
    void onLine(String line) {
      if (line.trim().isEmpty) return;
      if (!attached) {
        if (line.contains(consoleAttachedMarker)) {
          logger.detail(line);
          attached = true;
          launchProgress.complete();
          return;
        }
        if (!_consolePrefixRegex.hasMatch(line)) {
          logger.detail(line);
          launchOutput.add(line);
          return;
        }
        // App output means the console is attached, even if devicectl's
        // marker line never appeared.
        attached = true;
        launchProgress.complete();
      }

      final appLogLine = parseConsoleLine(line);
      if (appLogLine != null) {
        logger.info(appLogLine);
      } else {
        logger.detail(line);
      }
    }

    // Use allowMalformed to handle non-UTF8 bytes in the app's output.
    const decoder = Utf8Decoder(allowMalformed: true);
    final streamsDone = Future.wait([
      launchProcess.stdout
          .transform<String>(decoder)
          .transform<String>(const LineSplitter())
          .listen(onLine)
          .asFuture<void>(),
      launchProcess.stderr
          .transform<String>(decoder)
          .transform<String>(const LineSplitter())
          .listen(onLine)
          .asFuture<void>(),
    ]);

    final exitCode = await launchProcess.exitCode;
    await streamsDone;
    logger.detail('devicectl exited with code $exitCode');

    if (!attached) {
      launchProgress.fail(
        [
          'Unable to attach to the app (devicectl exited with code $exitCode)',
          ...launchOutput,
        ].join('\n'),
      );
      return false;
    }

    return true;
  }

  /// Matches the metadata prefix on os_log and syslog messages that
  /// `OS_ACTIVITY_DT_MODE` mirrors to the app's stderr, e.g.:
  ///   `2026-10-08 20:06:42.768621-0700 Runner[1234:5678] flutter: hello`
  ///
  /// Not anchored to the start of the line because the terminal that `script`
  /// provides can emit control characters ahead of the first line.
  static final _consolePrefixRegex = RegExp(
    r'\d{4}-\d{2}-\d{2} \S+ .+?\[\d+:\d+\] (.*)$',
  );

  /// Matches log lines written by the Flutter engine's FML logging, e.g.
  /// `[ERROR:flutter/shell/common/shell.cc(123)] ...`.
  static final _fmlLogRegex = RegExp(
    r'^\[(INFO|WARNING|ERROR|IMPORTANT|FATAL)',
  );

  /// Returns the part of a devicectl console [line] to show the user, or
  /// `null` if the line is system noise.
  ///
  /// Lines without os_log metadata (the app's stdout and stderr) are shown
  /// as-is. Of the lines with os_log metadata, only Dart `print` output
  /// (`flutter: ...`), Shorebird logs (`[shorebird] ...`), and Flutter engine
  /// logs are shown, with the metadata removed.
  @visibleForTesting
  static String? parseConsoleLine(String line) {
    final match = _consolePrefixRegex.firstMatch(line);
    if (match == null) return line;

    final message = match.group(1)!;
    if (message.startsWith('flutter:') ||
        message.contains('[shorebird]') ||
        _fmlLogRegex.hasMatch(message)) {
      return message;
    }
    return null;
  }

  /// Lists iOS devices that we can install and launch apps on. Excludes
  /// devices that devicectl reports as unavailable (e.g. paired but
  /// currently disconnected).
  Future<List<AppleDevice>> listAvailableIosDevices() =>
      _listIosDevices(availableOnly: true);

  /// Lists every iOS device devicectl knows about, including ones that are
  /// paired but currently unreachable (e.g. unplugged and locked, or
  /// momentarily off the local network). Useful for diagnosing why
  /// [listAvailableIosDevices] returned nothing.
  Future<List<AppleDevice>> listAllIosDevices() =>
      _listIosDevices(availableOnly: false);

  Future<List<AppleDevice>> _listIosDevices({
    required bool availableOnly,
  }) async {
    const failureErrorMessage = 'Failed to list devices';
    const timeout = Duration(seconds: 5);

    final args = [
      ...baseArgs,
      'list',
      'devices',
      '--timeout',
      '${timeout.inSeconds}',
    ];

    final Json jsonResult;
    try {
      jsonResult = await _runJsonCommand(args: args);
    } catch (error) {
      throw DevicectlException(
        message: failureErrorMessage,
        underlyingException: error,
      );
    }

    final devicesMatchValue = JsonPath(
      r'$.result.devices',
    ).read(jsonResult).firstOrNull?.value;
    if (devicesMatchValue == null) {
      throw DevicectlException(message: failureErrorMessage);
    }

    return (devicesMatchValue as List)
        .whereType<Json>()
        .map(AppleDevice.tryParse)
        .whereType<AppleDevice>()
        .where(
          (device) =>
              device.platform == 'iOS' &&
              (!availableOnly || device.isAvailable),
        )
        .toList();
  }

  /// Appends the `--json-output` argument to the list of command arguments,
  /// runs the command, and returns the parsed JSON output.
  Future<Json> _runJsonCommand({required List<String> args}) async {
    final tempDir = Directory.systemTemp.createTempSync();
    final jsonOutputFile = File(p.join(tempDir.path, 'devicectl.out.json'));

    final result = await process.run(executableName, [
      ...args,
      '--json-output',
      jsonOutputFile.path,
    ]);

    // The `devicectl` command will still write json output if it fails, so in
    // the event of a non-zero exit code, only throw a ProcessException if we
    // can't find the output file.
    if (!jsonOutputFile.existsSync()) {
      if (result.exitCode != ExitCode.success.code) {
        throw ProcessException(executableName, args, '${result.stderr}');
      } else {
        throw Exception(
          'Unable to find devicectl json output file: ${jsonOutputFile.path}',
        );
      }
    }

    final json = jsonDecode(jsonOutputFile.readAsStringSync()) as Json;

    // The json output file contains two top-level objects:
    //  - "info", which contains information about the command that was run
    //  - "result" or "error", which contains the actual output of the command
    //    or the error the occurred when attempting to run the command.
    //
    // If the output contains an error, throw an exception with the error
    final maybeError = _getErrorFromOutputJson(json);
    if (maybeError != null) {
      throw Exception(maybeError);
    }

    return json;
  }

  /// Parses the error message from the given [Json] output if one exists.
  /// Returns null if no error is found.
  String? _getErrorFromOutputJson(Json json) {
    final maybeErrorJson = json['error'] as Json?;
    if (maybeErrorJson == null) {
      return null;
    }

    // NSErrors can have infinitely nested underlying errors, and the original
    // error is usually the most useful, so we find the root error and use that
    // to get the error message.
    var rootError = NSError.fromJson(maybeErrorJson);
    while (rootError.userInfo.underlyingError?.error != null) {
      rootError = rootError.userInfo.underlyingError!.error!;
    }

    return rootError.userInfo.localizedFailureReason?.string ??
        rootError.userInfo.localizedDescription?.string ??
        rootError.userInfo.description?.string ??
        'unknown failure reason';
  }
}

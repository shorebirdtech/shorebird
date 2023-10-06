import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:io/io.dart';
import 'package:json_path/json_path.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/executables/devicectl/apple_device.dart';
import 'package:shorebird_cli/src/executables/devicectl/nserror.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

typedef BundleId = String;

/// {@template devicectl_exception}
/// Thrown when a [Devicectl] command fails.
/// {@endtemplate}
class DevicectlException implements Exception {
  /// {@macro devicectl_exception}
  DevicectlException({
    required this.message,
    this.underlyingException,
  });

  /// A message describing this exception.
  final String message;

  /// The exception that caused this exception to be thrown, if any.
  final Object? underlyingException;

  @override
  String toString() => '''
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
  static const executableName = 'xcrun';
  static const baseArgs = [
    'devicectl',
  ];

  /// Whether the `devicectl` command is available.
  Future<bool> _isAvailable() async {
    try {
      final result = await process.run(executableName, [
        ...baseArgs,
        '--version',
      ]);
      return result.exitCode == ExitCode.success.code;
    } catch (_) {
      return false;
    }
  }

  /// Returns the first available iOS device, or the device with the given
  /// [deviceId] if provided. Devices that are running iOS <17 are not
  /// "CoreDevice"s and are not visible to devicectl.
  Future<AppleDevice?> _deviceForLaunch({String? deviceId}) async {
    final devices = await listAvailableIosDevices();

    if (deviceId != null) {
      return devices.firstWhereOrNull((d) => d.identifier == deviceId);
    } else {
      return devices.firstOrNull;
    }
  }

  /// Whether we should use `devicectl` to install and launch the app on the
  /// device with the given [deviceId], or the first available device we find if
  /// [deviceId] is not provided.
  Future<bool> isSupported({String? deviceId}) async {
    if (!await _isAvailable()) {
      return false;
    }

    return await _deviceForLaunch(deviceId: deviceId) != null;
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
          JsonPath(r'$.result.installedApplications[0].bundleID')
              .read(jsonResult)
              .firstOrNull
              ?.value as String?;
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

  /// Installs and launches the given [runnerAppDirectory] on the device with
  /// the given [deviceId]. If no [deviceId] is provided, the first available
  /// device returned by [listAvailableIosDevices] will be used.
  Future<int> installAndLaunchApp({
    required Directory runnerAppDirectory,
    String? deviceId,
  }) async {
    final deviceProgress = logger.progress('Finding device for run');
    final device = await _deviceForLaunch(deviceId: deviceId);
    if (device == null) {
      deviceProgress.fail('No devices found');
      return ExitCode.software.code;
    }
    deviceProgress.complete();

    final installProgress = logger.progress('Installing app');

    final String bundleId;
    try {
      bundleId = await installApp(
        deviceId: device.identifier,
        runnerApp: runnerAppDirectory,
      );
    } catch (error) {
      installProgress.fail('Failed to install app: $error');
      return ExitCode.software.code;
    }
    installProgress.complete();

    final launchProgress = logger.progress('Launching app');
    try {
      await launchApp(
        deviceId: device.identifier,
        bundleId: bundleId,
      );
    } catch (error) {
      launchProgress.fail('Failed to launch app: $error');
      return ExitCode.software.code;
    }
    launchProgress.complete();

    return ExitCode.success.code;
  }

  /// Lists iOS devices that we can install and launch apps on.
  Future<List<AppleDevice>> listAvailableIosDevices() async {
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

    final devicesMatchValue =
        JsonPath(r'$.result.devices').read(jsonResult).firstOrNull?.value;
    if (devicesMatchValue == null) {
      throw DevicectlException(message: failureErrorMessage);
    }

    return (devicesMatchValue as List)
        .whereType<Json>()
        .map(AppleDevice.fromJson)
        .where((device) => device.platform == 'iOS' && device.isAvailable)
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
        'unknown failure reason';
  }
}

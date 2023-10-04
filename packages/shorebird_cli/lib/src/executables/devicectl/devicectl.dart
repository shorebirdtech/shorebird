import 'dart:convert';

import 'package:io/io.dart';
import 'package:json_path/json_path.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/executables/devicectl/apple_device.dart';
import 'package:shorebird_cli/src/executables/devicectl/nserror.dart';
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
  final Exception? underlyingException;

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
        underlyingException: error as Exception,
      );
    }

    final String bundleId;
    try {
      final bundleIds = JsonPath(r'$.result.installedApplications[0].bundleID')
          .read(jsonResult);
      final maybeBundleId = bundleIds.firstOrNull?.value as String?;
      if (maybeBundleId == null) {
        throw Exception(
          'Unable to find installed app bundleID in devicectl output',
        );
      }

      bundleId = maybeBundleId;
    } catch (e) {
      throw DevicectlException(
        message: failureErrorMessage,
        underlyingException: e as Exception,
      );
    }

    return bundleId;
  }

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
        underlyingException: error as Exception,
      );
    }
  }

  Future<List<AppleDevice>> listIosDevices() async {
    const failureErrorMessage = 'Failed to list devices';

    final args = [
      ...baseArgs,
      'list',
      'devices',
    ];

    final Json jsonResult;
    try {
      jsonResult = await _runJsonCommand(args: args);
    } catch (error) {
      throw DevicectlException(
        message: failureErrorMessage,
        underlyingException: error as Exception,
      );
    }

    final devicesMatch =
        JsonPath(r'$.result.devices').read(jsonResult).firstOrNull;
    if (devicesMatch?.value == null) {
      throw DevicectlException(message: failureErrorMessage);
    }

    return (devicesMatch!.value! as List)
        .whereType<Json>()
        .map(AppleDevice.fromJson)
        .where((device) => device.platform == 'iOS')
        .toList();
  }

  /// Appends the `--json-output` argument to the list of command arguments,
  /// runs the command, and returns the parsed JSON output.
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

    final json = jsonDecode(jsonOutputFile.readAsStringSync()) as Json;

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

    var rootError = NSError.fromJson(maybeErrorJson);
    while (rootError.userInfo.underlyingError?.error != null) {
      rootError = rootError.userInfo.underlyingError!.error!;
    }

    return rootError.userInfo.localizedFailureReason?.string ??
        'uknown failure reason';
  }
}

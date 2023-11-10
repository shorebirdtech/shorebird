import 'package:json_annotation/json_annotation.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/extensions/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

part 'apple_device.g.dart';

/// {@template apple_device}
/// A pared-down version of a CoreDevice, as represented in the JSON output of
/// `xcrun devicectl list devices`.
/// {@endtemplate}
@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)

/// {@macro apple_device}
class AppleDevice {
  const AppleDevice({
    required this.deviceProperties,
    required this.hardwareProperties,
    required this.connectionProperties,
  });

  /// Creates an [AppleDevice] from JSON.
  static AppleDevice fromJson(Json json) => _$AppleDeviceFromJson(json);

  /// Information about the device itself.
  final DeviceProperties deviceProperties;

  /// Information about the device's hardware.
  final HardwareProperties hardwareProperties;

  /// Information about the device's connection.
  final ConnectionProperties connectionProperties;

  /// The device's platform (e.g., "iOS").
  String get platform => hardwareProperties.platform;

  /// Human-readable name of the device (e.g., "Joe's iPhone").
  String get name => deviceProperties.name;

  /// The device's OS version as a string (e.g., "14.4.1").
  String? get osVersionString => deviceProperties.osVersionNumber;

  /// The device's OS version as a [Version], or `null` if the version string
  /// cannot be parsed.
  Version? get osVersion =>
      osVersionString == null ? null : tryParseVersion(osVersionString!);

  /// Whether the device is available for use. See the docs for
  /// [ConnectionProperties.tunnelState] for more information about known
  /// tunnelState values and what they (seem to) represent.
  bool get isAvailable => connectionProperties.tunnelState != 'unavailable';

  /// The device's unique identifier of the form 12345678-1234567890ABCDEF
  String get udid => hardwareProperties.udid;

  /// Whether the device is connected via USB.
  bool get isWired => connectionProperties.transportType == 'wired';

  @override
  String toString() => '$name ($osVersionString ${hardwareProperties.udid})';
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class HardwareProperties {
  const HardwareProperties({required this.platform, required this.udid});

  /// The device's platform (e.g., "iOS").
  final String platform;

  /// The unique identifier of this device
  final String udid;

  static HardwareProperties fromJson(Json json) =>
      _$HardwarePropertiesFromJson(json);
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class DeviceProperties {
  const DeviceProperties({required this.name, this.osVersionNumber});

  /// Human-readable name of the device (e.g., "Joe's iPhone").
  final String name;

  /// The device's OS version as a string (e.g., "14.4.1").
  final String? osVersionNumber;

  static DeviceProperties fromJson(Json json) =>
      _$DevicePropertiesFromJson(json);
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class ConnectionProperties {
  const ConnectionProperties({required this.tunnelState, this.transportType});

  /// How the device is connected. Values seen in development include
  /// "localNetwork" and "wired". Will be absent if the device is not connected.
  final String? transportType;

  /// The device's connection state. Values seen in development (as devicectl
  /// is seemingly undocumented) include:
  /// - "disconnected" when the device is connected via USB or wifi. I presume
  ///   "connected" indicates that a process is attached to the device, but I
  ///   have not seen this value in practice.
  /// - "unavailable" when the device is not connected via USB or wifi.
  final String tunnelState;

  static ConnectionProperties fromJson(Json json) =>
      _$ConnectionPropertiesFromJson(json);
}

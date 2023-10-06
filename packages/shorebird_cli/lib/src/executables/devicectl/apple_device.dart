import 'package:json_annotation/json_annotation.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/extensions/version.dart';

part 'apple_device.g.dart';

/// {@template apple_device}
/// A pared-down version of a CoreDevice, as represented in the JSON output of
/// `xcrun devicectl list devices`.
/// {@endtemplate}
@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)

/// {@macro apple_device}
class AppleDevice {
  const AppleDevice({
    required this.identifier,
    required this.deviceProperties,
    required this.hardwareProperties,
    required this.connectionProperties,
  });

  /// Creates an [AppleDevice] from JSON.
  static AppleDevice fromJson(Map<String, dynamic> json) =>
      _$AppleDeviceFromJson(json);

  /// The device's unique identifier of the form
  /// DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF.
  final String identifier;

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
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class HardwareProperties {
  const HardwareProperties({required this.platform});

  /// The device's platform (e.g., "iOS").
  final String platform;

  static HardwareProperties fromJson(Map<String, dynamic> json) =>
      _$HardwarePropertiesFromJson(json);
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class DeviceProperties {
  const DeviceProperties({required this.name, this.osVersionNumber});

  /// Human-readable name of the device (e.g., "Joe's iPhone").
  final String name;

  /// The device's OS version as a string (e.g., "14.4.1").
  final String? osVersionNumber;

  static DeviceProperties fromJson(Map<String, dynamic> json) =>
      _$DevicePropertiesFromJson(json);
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class ConnectionProperties {
  const ConnectionProperties({required this.tunnelState});

  /// The device's connection state. Values seen in development (as devicectl
  /// is seemingly undocumented) include:
  /// - "disconnected" when the device is connected via USB or wifi. I presume
  ///   "connected" indicates that a process is attached to the device, but I
  ///   have not seen this value in practice.
  /// - "unavailable" when the device is not connected via USB or wifi.
  final String tunnelState;

  static ConnectionProperties fromJson(Map<String, dynamic> json) =>
      _$ConnectionPropertiesFromJson(json);
}

import 'package:json_annotation/json_annotation.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/extensions/version.dart';

part 'apple_device.g.dart';

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class AppleDevice {
  AppleDevice({
    required this.identifier,
    required this.deviceProperties,
    required this.hardwareProperties,
    required this.connectionProperties,
  });

  static AppleDevice fromJson(Map<String, dynamic> json) =>
      _$AppleDeviceFromJson(json);

  /// The device's unique identifier.
  final String identifier;

  final DeviceProperties deviceProperties;

  final HardwareProperties hardwareProperties;

  final ConnectionProperties connectionProperties;

  String get platform => hardwareProperties.platform;

  String get name => deviceProperties.name;

  String get osVersionString => deviceProperties.osVersionNumber;

  Version get osVersion => VersionParsing.tryParse(osVersionString)!;

  bool get isAavailable => connectionProperties.tunnelState != 'unavailable';
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class HardwareProperties {
  HardwareProperties({required this.platform});

  /// The device's platform (e.g., "iOS").
  final String platform;

  static HardwareProperties fromJson(Map<String, dynamic> json) =>
      _$HardwarePropertiesFromJson(json);
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class DeviceProperties {
  DeviceProperties({required this.name, required this.osVersionNumber});

  /// Human-readable name of the device (e.g., "Joe's iPhone").
  final String name;

  /// The device's OS version as a string (e.g., "14.4.1").
  final String osVersionNumber;

  static DeviceProperties fromJson(Map<String, dynamic> json) =>
      _$DevicePropertiesFromJson(json);
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class ConnectionProperties {
  ConnectionProperties({required this.tunnelState});

  final String tunnelState;

  static ConnectionProperties fromJson(Map<String, dynamic> json) =>
      _$ConnectionPropertiesFromJson(json);
}

import 'package:json_annotation/json_annotation.dart';

part 'apple_device.g.dart';

@JsonSerializable(createToJson: false, fieldRename: FieldRename.none)
class AppleDevice {
  AppleDevice({
    required this.identifier,
    required this.deviceProperties,
    required this.hardwareProperties,
  });

  static AppleDevice fromJson(Map<String, dynamic> json) =>
      _$AppleDeviceFromJson(json);

  /// The device's unique identifier.
  final String identifier;

  final DeviceProperties deviceProperties;

  final HardwareProperties hardwareProperties;

  String get platform => hardwareProperties.platform;

  String get name => deviceProperties.name;

  String get osVersionString => deviceProperties.osVersionNumber;
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

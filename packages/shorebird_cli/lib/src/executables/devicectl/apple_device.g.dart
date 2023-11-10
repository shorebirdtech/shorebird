// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, strict_raw_type, unnecessary_lambdas

part of 'apple_device.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppleDevice _$AppleDeviceFromJson(Map<String, dynamic> json) => $checkedCreate(
      'AppleDevice',
      json,
      ($checkedConvert) {
        final val = AppleDevice(
          deviceProperties: $checkedConvert('deviceProperties',
              (v) => DeviceProperties.fromJson(v as Map<String, dynamic>)),
          hardwareProperties: $checkedConvert('hardwareProperties',
              (v) => HardwareProperties.fromJson(v as Map<String, dynamic>)),
          connectionProperties: $checkedConvert('connectionProperties',
              (v) => ConnectionProperties.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
    );

HardwareProperties _$HardwarePropertiesFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'HardwareProperties',
      json,
      ($checkedConvert) {
        final val = HardwareProperties(
          platform: $checkedConvert('platform', (v) => v as String),
          udid: $checkedConvert('udid', (v) => v as String),
        );
        return val;
      },
    );

DeviceProperties _$DevicePropertiesFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'DeviceProperties',
      json,
      ($checkedConvert) {
        final val = DeviceProperties(
          name: $checkedConvert('name', (v) => v as String),
          osVersionNumber:
              $checkedConvert('osVersionNumber', (v) => v as String?),
        );
        return val;
      },
    );

ConnectionProperties _$ConnectionPropertiesFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'ConnectionProperties',
      json,
      ($checkedConvert) {
        final val = ConnectionProperties(
          tunnelState: $checkedConvert('tunnelState', (v) => v as String),
          transportType: $checkedConvert('transportType', (v) => v as String?),
        );
        return val;
      },
    );

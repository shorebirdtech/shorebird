// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'build_environment_metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BuildEnvironmentMetadata _$BuildEnvironmentMetadataFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'BuildEnvironmentMetadata',
      json,
      ($checkedConvert) {
        final val = BuildEnvironmentMetadata(
          shorebirdVersion:
              $checkedConvert('shorebird_version', (v) => v as String),
          operatingSystem:
              $checkedConvert('operating_system', (v) => v as String),
          operatingSystemVersion:
              $checkedConvert('operating_system_version', (v) => v as String),
          xcodeVersion: $checkedConvert('xcode_version', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {
        'shorebirdVersion': 'shorebird_version',
        'operatingSystem': 'operating_system',
        'operatingSystemVersion': 'operating_system_version',
        'xcodeVersion': 'xcode_version'
      },
    );

Map<String, dynamic> _$BuildEnvironmentMetadataToJson(
        BuildEnvironmentMetadata instance) =>
    <String, dynamic>{
      'shorebird_version': instance.shorebirdVersion,
      'operating_system': instance.operatingSystem,
      'operating_system_version': instance.operatingSystemVersion,
      'xcode_version': instance.xcodeVersion,
    };

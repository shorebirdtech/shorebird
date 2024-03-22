// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'update_release_metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdateReleaseMetadata _$UpdateReleaseMetadataFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'UpdateReleaseMetadata',
      json,
      ($checkedConvert) {
        final val = UpdateReleaseMetadata(
          generatedApks: $checkedConvert('generated_apks', (v) => v as bool?),
          environment: $checkedConvert(
              'environment',
              (v) =>
                  BuildEnvironmentMetadata.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
      fieldKeyMap: const {'generatedApks': 'generated_apks'},
    );

Map<String, dynamic> _$UpdateReleaseMetadataToJson(
        UpdateReleaseMetadata instance) =>
    <String, dynamic>{
      'generated_apks': instance.generatedApks,
      'environment': instance.environment.toJson(),
    };

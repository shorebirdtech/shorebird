// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'get_release_artifacts_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetReleaseArtifactsResponse _$GetReleaseArtifactsResponseFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'GetReleaseArtifactsResponse',
      json,
      ($checkedConvert) {
        final val = GetReleaseArtifactsResponse(
          artifacts: $checkedConvert(
              'artifacts',
              (v) => (v as List<dynamic>)
                  .map((e) =>
                      ReleaseArtifact.fromJson(e as Map<String, dynamic>))
                  .toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$GetReleaseArtifactsResponseToJson(
        GetReleaseArtifactsResponse instance) =>
    <String, dynamic>{
      'artifacts': instance.artifacts.map((e) => e.toJson()).toList(),
    };

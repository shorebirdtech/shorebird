// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_patch_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreatePatchResponse _$CreatePatchResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CreatePatchResponse',
      json,
      ($checkedConvert) {
        final val = CreatePatchResponse(
          id: $checkedConvert('id', (v) => v as int),
          number: $checkedConvert('number', (v) => v as int),
          artifactUploadUrls: $checkedConvert('artifact_upload_urls',
              (v) => ArtifactUploadUrls.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
      fieldKeyMap: const {'artifactUploadUrls': 'artifact_upload_urls'},
    );

Map<String, dynamic> _$CreatePatchResponseToJson(
        CreatePatchResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'number': instance.number,
      'artifact_upload_urls': instance.artifactUploadUrls.toJson(),
    };

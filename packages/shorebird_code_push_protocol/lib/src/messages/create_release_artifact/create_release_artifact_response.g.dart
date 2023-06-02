// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_release_artifact_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreateReleaseArtifactResponse _$CreateReleaseArtifactResponseFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CreateReleaseArtifactResponse',
      json,
      ($checkedConvert) {
        final val = CreateReleaseArtifactResponse(
          id: $checkedConvert('id', (v) => v as int),
          releaseId: $checkedConvert('release_id', (v) => v as int),
          arch: $checkedConvert('arch', (v) => v as String),
          platform: $checkedConvert('platform', (v) => v as String),
          hash: $checkedConvert('hash', (v) => v as String),
          size: $checkedConvert('size',
              (v) => CreateReleaseArtifactResponse._parseStringToInt(v)),
          uploadUrl: $checkedConvert('upload_url', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'releaseId': 'release_id', 'uploadUrl': 'upload_url'},
    );

Map<String, dynamic> _$CreateReleaseArtifactResponseToJson(
        CreateReleaseArtifactResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'release_id': instance.releaseId,
      'arch': instance.arch,
      'platform': instance.platform,
      'hash': instance.hash,
      'size': CreateReleaseArtifactResponse._parseIntToString(instance.size),
      'upload_url': instance.uploadUrl,
    };

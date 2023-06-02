// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_patch_artifact_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreatePatchArtifactResponse _$CreatePatchArtifactResponseFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CreatePatchArtifactResponse',
      json,
      ($checkedConvert) {
        final val = CreatePatchArtifactResponse(
          arch: $checkedConvert('arch', (v) => v as String),
          platform: $checkedConvert('platform', (v) => v as String),
          hash: $checkedConvert('hash', (v) => v as String),
          size: $checkedConvert(
              'size', (v) => CreatePatchArtifactResponse._parseStringToInt(v)),
          url: $checkedConvert('url', (v) => v as String?),
        );
        return val;
      },
    );

Map<String, dynamic> _$CreatePatchArtifactResponseToJson(
        CreatePatchArtifactResponse instance) =>
    <String, dynamic>{
      'arch': instance.arch,
      'platform': instance.platform,
      'hash': instance.hash,
      'url': instance.url,
      'size': CreatePatchArtifactResponse._parseIntToString(instance.size),
    };

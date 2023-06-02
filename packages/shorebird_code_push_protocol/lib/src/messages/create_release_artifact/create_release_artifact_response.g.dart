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
          arch: $checkedConvert('arch', (v) => v as String),
          platform: $checkedConvert('platform', (v) => v as String),
          hash: $checkedConvert('hash', (v) => v as String),
          size: $checkedConvert('size',
              (v) => CreateReleaseArtifactResponse._parseStringToInt(v)),
          url: $checkedConvert('url', (v) => v as String),
        );
        return val;
      },
    );

Map<String, dynamic> _$CreateReleaseArtifactResponseToJson(
        CreateReleaseArtifactResponse instance) =>
    <String, dynamic>{
      'arch': instance.arch,
      'platform': instance.platform,
      'hash': instance.hash,
      'size': CreateReleaseArtifactResponse._parseIntToString(instance.size),
      'url': instance.url,
    };

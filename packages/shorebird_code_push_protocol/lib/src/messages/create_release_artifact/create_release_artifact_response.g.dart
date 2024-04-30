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
          id: $checkedConvert('id', (v) => (v as num).toInt()),
          releaseId: $checkedConvert('release_id', (v) => (v as num).toInt()),
          arch: $checkedConvert('arch', (v) => v as String),
          platform: $checkedConvert(
              'platform', (v) => $enumDecode(_$ReleasePlatformEnumMap, v)),
          hash: $checkedConvert('hash', (v) => v as String),
          size: $checkedConvert('size', (v) => (v as num).toInt()),
          url: $checkedConvert('url', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'releaseId': 'release_id'},
    );

Map<String, dynamic> _$CreateReleaseArtifactResponseToJson(
        CreateReleaseArtifactResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'release_id': instance.releaseId,
      'arch': instance.arch,
      'platform': _$ReleasePlatformEnumMap[instance.platform]!,
      'hash': instance.hash,
      'size': instance.size,
      'url': instance.url,
    };

const _$ReleasePlatformEnumMap = {
  ReleasePlatform.android: 'android',
  ReleasePlatform.ios: 'ios',
};

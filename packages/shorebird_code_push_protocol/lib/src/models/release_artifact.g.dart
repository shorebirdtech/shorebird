// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'release_artifact.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReleaseArtifact _$ReleaseArtifactFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ReleaseArtifact',
      json,
      ($checkedConvert) {
        final val = ReleaseArtifact(
          id: $checkedConvert('id', (v) => v as int),
          releaseId: $checkedConvert('release_id', (v) => v as int),
          arch: $checkedConvert('arch', (v) => v as String),
          platform: $checkedConvert(
              'platform', (v) => $enumDecode(_$ReleasePlatformEnumMap, v)),
          hash: $checkedConvert('hash', (v) => v as String),
          size: $checkedConvert('size', (v) => v as int),
          url: $checkedConvert('url', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'releaseId': 'release_id'},
    );

Map<String, dynamic> _$ReleaseArtifactToJson(ReleaseArtifact instance) =>
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

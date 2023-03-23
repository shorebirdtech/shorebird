// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'artifact.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Artifact _$ArtifactFromJson(Map<String, dynamic> json) => $checkedCreate(
      'Artifact',
      json,
      ($checkedConvert) {
        final val = Artifact(
          id: $checkedConvert('id', (v) => v as int),
          patchId: $checkedConvert('patch_id', (v) => v as int),
          arch: $checkedConvert('arch', (v) => v as String),
          platform: $checkedConvert('platform', (v) => v as String),
          hash: $checkedConvert('hash', (v) => v as String),
          url: $checkedConvert('url', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'patchId': 'patch_id'},
    );

Map<String, dynamic> _$ArtifactToJson(Artifact instance) => <String, dynamic>{
      'id': instance.id,
      'patch_id': instance.patchId,
      'arch': instance.arch,
      'platform': instance.platform,
      'hash': instance.hash,
      'url': instance.url,
    };

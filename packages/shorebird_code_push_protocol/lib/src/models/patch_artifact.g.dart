// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'patch_artifact.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PatchArtifact _$PatchArtifactFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'PatchArtifact',
      json,
      ($checkedConvert) {
        final val = PatchArtifact(
          id: $checkedConvert('id', (v) => v as int),
          patchId: $checkedConvert('patch_id', (v) => v as int),
          arch: $checkedConvert('arch', (v) => v as String),
          platform: $checkedConvert('platform', (v) => v as String),
          hash: $checkedConvert('hash', (v) => v as String),
          size: $checkedConvert('size', (v) => v as int),
          url: $checkedConvert('url', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'patchId': 'patch_id'},
    );

Map<String, dynamic> _$PatchArtifactToJson(PatchArtifact instance) =>
    <String, dynamic>{
      'id': instance.id,
      'patch_id': instance.patchId,
      'arch': instance.arch,
      'platform': instance.platform,
      'hash': instance.hash,
      'size': instance.size,
      'url': instance.url,
    };

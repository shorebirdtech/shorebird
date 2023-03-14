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
          arch: $checkedConvert('arch', (v) => v as String),
          platform: $checkedConvert('platform', (v) => v as String),
          url: $checkedConvert('url', (v) => v as String),
          hash: $checkedConvert('hash', (v) => v as String),
        );
        return val;
      },
    );

Map<String, dynamic> _$ArtifactToJson(Artifact instance) => <String, dynamic>{
      'arch': instance.arch,
      'platform': instance.platform,
      'url': instance.url,
      'hash': instance.hash,
    };

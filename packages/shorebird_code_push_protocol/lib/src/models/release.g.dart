// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'release.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Release _$ReleaseFromJson(Map<String, dynamic> json) => $checkedCreate(
      'Release',
      json,
      ($checkedConvert) {
        final val = Release(
          id: $checkedConvert('id', (v) => v as int),
          appId: $checkedConvert('app_id', (v) => v as String),
          version: $checkedConvert('version', (v) => v as String),
          displayName: $checkedConvert('display_name', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {'appId': 'app_id', 'displayName': 'display_name'},
    );

Map<String, dynamic> _$ReleaseToJson(Release instance) => <String, dynamic>{
      'id': instance.id,
      'app_id': instance.appId,
      'version': instance.version,
      'display_name': instance.displayName,
    };

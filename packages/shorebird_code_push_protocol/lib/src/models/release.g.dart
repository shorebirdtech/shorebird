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
          version: $checkedConvert('version', (v) => v as String),
          patches: $checkedConvert(
              'patches',
              (v) => (v as List<dynamic>?)
                  ?.map((e) => Patch.fromJson(e as Map<String, dynamic>))
                  .toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$ReleaseToJson(Release instance) => <String, dynamic>{
      'version': instance.version,
      'patches': instance.patches.map((e) => e.toJson()).toList(),
    };

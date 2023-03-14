// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'patch.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Patch _$PatchFromJson(Map<String, dynamic> json) => $checkedCreate(
      'Patch',
      json,
      ($checkedConvert) {
        final val = Patch(
          number: $checkedConvert('number', (v) => v as int),
          artifacts: $checkedConvert(
              'artifacts',
              (v) =>
                  (v as List<dynamic>?)
                      ?.map((e) => Artifact.fromJson(e as Map<String, dynamic>))
                      .toList() ??
                  const []),
          channels: $checkedConvert(
              'channels',
              (v) =>
                  (v as List<dynamic>?)?.map((e) => e as String).toList() ??
                  const []),
        );
        return val;
      },
    );

Map<String, dynamic> _$PatchToJson(Patch instance) => <String, dynamic>{
      'number': instance.number,
      'channels': instance.channels,
      'artifacts': instance.artifacts.map((e) => e.toJson()).toList(),
    };

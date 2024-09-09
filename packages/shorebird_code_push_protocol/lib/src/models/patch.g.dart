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
          id: $checkedConvert('id', (v) => (v as num).toInt()),
          number: $checkedConvert('number', (v) => (v as num).toInt()),
        );
        return val;
      },
    );

Map<String, dynamic> _$PatchToJson(Patch instance) => <String, dynamic>{
      'id': instance.id,
      'number': instance.number,
    };

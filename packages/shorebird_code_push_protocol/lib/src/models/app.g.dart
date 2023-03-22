// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'app.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

App _$AppFromJson(Map<String, dynamic> json) => $checkedCreate(
      'App',
      json,
      ($checkedConvert) {
        final val = App(
          id: $checkedConvert('id', (v) => v as String),
          displayName: $checkedConvert('display_name', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'displayName': 'display_name'},
    );

Map<String, dynamic> _$AppToJson(App instance) => <String, dynamic>{
      'id': instance.id,
      'display_name': instance.displayName,
    };

// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'account.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Account _$AccountFromJson(Map<String, dynamic> json) => $checkedCreate(
      'Account',
      json,
      ($checkedConvert) {
        final val = Account(
          apiKey: $checkedConvert('api_key', (v) => v as String),
          apps: $checkedConvert(
              'apps',
              (v) => (v as List<dynamic>?)
                  ?.map((e) => App.fromJson(e as Map<String, dynamic>))
                  .toList()),
        );
        return val;
      },
      fieldKeyMap: const {'apiKey': 'api_key'},
    );

Map<String, dynamic> _$AccountToJson(Account instance) => <String, dynamic>{
      'apps': instance.apps.map((e) => e.toJson()).toList(),
      'api_key': instance.apiKey,
    };

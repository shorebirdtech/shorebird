// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'registry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Registry _$RegistryFromJson(Map<String, dynamic> json) => $checkedCreate(
      'Registry',
      json,
      ($checkedConvert) {
        final val = Registry(
          accounts: $checkedConvert(
              'accounts',
              (v) =>
                  (v as List<dynamic>?)
                      ?.map((e) => Account.fromJson(e as Map<String, dynamic>))
                      .toList() ??
                  const []),
        );
        return val;
      },
    );

Map<String, dynamic> _$RegistryToJson(Registry instance) => <String, dynamic>{
      'accounts': instance.accounts.map((e) => e.toJson()).toList(),
    };

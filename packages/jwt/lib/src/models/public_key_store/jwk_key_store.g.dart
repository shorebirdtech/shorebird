// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'jwk_key_store.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

JwkKeyStore _$JwkKeyStoreFromJson(Map<String, dynamic> json) => $checkedCreate(
      'JwkKeyStore',
      json,
      ($checkedConvert) {
        final val = JwkKeyStore(
          keys: $checkedConvert(
              'keys',
              (v) => (v as List<dynamic>)
                  .map((e) => Jwk.fromJson(e as Map<String, dynamic>))
                  .toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$JwkKeyStoreToJson(JwkKeyStore instance) =>
    <String, dynamic>{
      'keys': instance.keys,
    };

// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'jwk.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Jwk _$JwkFromJson(Map<String, dynamic> json) => $checkedCreate(
      'Jwk',
      json,
      ($checkedConvert) {
        final val = Jwk(
          kty: $checkedConvert('kty', (v) => v as String),
          use: $checkedConvert('use', (v) => v as String),
          kid: $checkedConvert('kid', (v) => v as String),
          x5c: $checkedConvert('x5c',
              (v) => (v as List<dynamic>).map((e) => e as String).toList()),
          x5t: $checkedConvert('x5t', (v) => v as String),
          n: $checkedConvert('n', (v) => v as String),
          e: $checkedConvert('e', (v) => v as String),
        );
        return val;
      },
    );

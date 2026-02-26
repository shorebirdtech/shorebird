// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, document_ignores

part of 'rsa_jwk.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RsaJwk _$RsaJwkFromJson(Map<String, dynamic> json) =>
    $checkedCreate('RsaJwk', json, ($checkedConvert) {
      final val = RsaJwk(
        kty: $checkedConvert('kty', (v) => v as String),
        use: $checkedConvert('use', (v) => v as String),
        kid: $checkedConvert('kid', (v) => v as String),
        n: $checkedConvert('n', (v) => v as String),
        e: $checkedConvert('e', (v) => v as String),
        alg: $checkedConvert('alg', (v) => v as String?),
      );
      return val;
    });

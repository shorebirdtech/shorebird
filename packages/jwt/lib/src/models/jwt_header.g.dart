// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'jwt_header.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

JwtHeader _$JwtHeaderFromJson(Map<String, dynamic> json) => $checkedCreate(
      'JwtHeader',
      json,
      ($checkedConvert) {
        final val = JwtHeader(
          alg: $checkedConvert('alg', (v) => v as String),
          kid: $checkedConvert('kid', (v) => v as String),
          typ: $checkedConvert('typ', (v) => v as String),
        );
        return val;
      },
    );

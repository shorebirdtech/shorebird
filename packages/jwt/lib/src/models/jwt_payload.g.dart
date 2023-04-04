// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'jwt_payload.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

JwtPayload _$JwtPayloadFromJson(Map<String, dynamic> json) => $checkedCreate(
      'JwtPayload',
      json,
      ($checkedConvert) {
        final val = JwtPayload(
          exp: $checkedConvert('exp', (v) => v as int),
          iat: $checkedConvert('iat', (v) => v as int),
          aud: $checkedConvert('aud', (v) => v as String),
          iss: $checkedConvert('iss', (v) => v as String),
          sub: $checkedConvert('sub', (v) => v as String),
          authTime: $checkedConvert('auth_time', (v) => v as int),
        );
        return val;
      },
      fieldKeyMap: const {'authTime': 'auth_time'},
    );

// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, strict_raw_type, unnecessary_lambdas

part of 'ci_token.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CiToken _$CiTokenFromJson(Map<String, dynamic> json) => $checkedCreate(
      'CiToken',
      json,
      ($checkedConvert) {
        final val = CiToken(
          refreshToken: $checkedConvert('refresh_token', (v) => v as String),
          authProvider: $checkedConvert(
              'auth_provider', (v) => $enumDecode(_$AuthProviderEnumMap, v)),
        );
        return val;
      },
      fieldKeyMap: const {
        'refreshToken': 'refresh_token',
        'authProvider': 'auth_provider'
      },
    );

Map<String, dynamic> _$CiTokenToJson(CiToken instance) => <String, dynamic>{
      'refresh_token': instance.refreshToken,
      'auth_provider': _$AuthProviderEnumMap[instance.authProvider]!,
    };

const _$AuthProviderEnumMap = {
  AuthProvider.google: 'google',
  AuthProvider.microsoft: 'microsoft',
};

// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_user_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreateUserRequest _$CreateUserRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CreateUserRequest',
      json,
      ($checkedConvert) {
        final val = CreateUserRequest(
          name: $checkedConvert('name', (v) => v as String),
        );
        return val;
      },
    );

Map<String, dynamic> _$CreateUserRequestToJson(CreateUserRequest instance) =>
    <String, dynamic>{
      'name': instance.name,
    };

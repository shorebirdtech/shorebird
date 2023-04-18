// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_app_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreateAppRequest _$CreateAppRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CreateAppRequest',
      json,
      ($checkedConvert) {
        final val = CreateAppRequest(
          displayName: $checkedConvert('display_name', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'displayName': 'display_name'},
    );

Map<String, dynamic> _$CreateAppRequestToJson(CreateAppRequest instance) =>
    <String, dynamic>{
      'display_name': instance.displayName,
    };

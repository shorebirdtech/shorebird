// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_release_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreateReleaseRequest _$CreateReleaseRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CreateReleaseRequest',
      json,
      ($checkedConvert) {
        final val = CreateReleaseRequest(
          appId: $checkedConvert('app_id', (v) => v as String),
          version: $checkedConvert('version', (v) => v as String),
          displayName: $checkedConvert('display_name', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {'appId': 'app_id', 'displayName': 'display_name'},
    );

Map<String, dynamic> _$CreateReleaseRequestToJson(
        CreateReleaseRequest instance) =>
    <String, dynamic>{
      'app_id': instance.appId,
      'version': instance.version,
      'display_name': instance.displayName,
    };

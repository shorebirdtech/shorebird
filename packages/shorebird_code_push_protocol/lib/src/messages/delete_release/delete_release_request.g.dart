// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'delete_release_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeleteReleaseRequest _$DeleteReleaseRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'DeleteReleaseRequest',
      json,
      ($checkedConvert) {
        final val = DeleteReleaseRequest(
          appId: $checkedConvert('app_id', (v) => v as String),
          version: $checkedConvert('version', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'appId': 'app_id'},
    );

Map<String, dynamic> _$DeleteReleaseRequestToJson(
        DeleteReleaseRequest instance) =>
    <String, dynamic>{
      'app_id': instance.appId,
      'version': instance.version,
    };

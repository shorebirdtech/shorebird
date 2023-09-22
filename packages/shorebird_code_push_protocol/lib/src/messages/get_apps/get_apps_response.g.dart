// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'get_apps_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetAppsResponse _$GetAppsResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'GetAppsResponse',
      json,
      ($checkedConvert) {
        final val = GetAppsResponse(
          apps: $checkedConvert(
              'apps',
              (v) => (v as List<dynamic>)
                  .map((e) => AppMetadata.fromJson(e as Map<String, dynamic>))
                  .toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$GetAppsResponseToJson(GetAppsResponse instance) =>
    <String, dynamic>{
      'apps': instance.apps.map((e) => e.toJson()).toList(),
    };

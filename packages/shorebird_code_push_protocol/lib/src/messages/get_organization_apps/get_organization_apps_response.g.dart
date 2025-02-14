// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'get_organization_apps_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetOrganizationAppsResponse _$GetOrganizationAppsResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('GetOrganizationAppsResponse', json, ($checkedConvert) {
  final val = GetOrganizationAppsResponse(
    apps: $checkedConvert(
      'apps',
      (v) =>
          (v as List<dynamic>)
              .map((e) => AppMetadata.fromJson(e as Map<String, dynamic>))
              .toList(),
    ),
  );
  return val;
});

Map<String, dynamic> _$GetOrganizationAppsResponseToJson(
  GetOrganizationAppsResponse instance,
) => <String, dynamic>{'apps': instance.apps.map((e) => e.toJson()).toList()};

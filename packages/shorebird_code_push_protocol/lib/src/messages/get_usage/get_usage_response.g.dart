// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'get_usage_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetUsageResponse _$GetUsageResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'GetUsageResponse',
      json,
      ($checkedConvert) {
        final val = GetUsageResponse(
          apps: $checkedConvert(
              'apps',
              (v) => (v as List<dynamic>)
                  .map((e) => AppUsage.fromJson(e as Map<String, dynamic>))
                  .toList()),
          patchInstallLimit:
              $checkedConvert('patch_install_limit', (v) => v as int?),
          currentPeriodStart: $checkedConvert(
              'current_period_start', (v) => DateTime.parse(v as String)),
          currentPeriodEnd: $checkedConvert(
              'current_period_end', (v) => DateTime.parse(v as String)),
        );
        return val;
      },
      fieldKeyMap: const {
        'patchInstallLimit': 'patch_install_limit',
        'currentPeriodStart': 'current_period_start',
        'currentPeriodEnd': 'current_period_end'
      },
    );

Map<String, dynamic> _$GetUsageResponseToJson(GetUsageResponse instance) =>
    <String, dynamic>{
      'apps': instance.apps.map((e) => e.toJson()).toList(),
      'current_period_start': instance.currentPeriodStart.toIso8601String(),
      'current_period_end': instance.currentPeriodEnd.toIso8601String(),
      'patch_install_limit': instance.patchInstallLimit,
    };

AppUsage _$AppUsageFromJson(Map<String, dynamic> json) => $checkedCreate(
      'AppUsage',
      json,
      ($checkedConvert) {
        final val = AppUsage(
          id: $checkedConvert('id', (v) => v as String),
          name: $checkedConvert('name', (v) => v as String),
          patchInstallCount:
              $checkedConvert('patch_install_count', (v) => v as int),
        );
        return val;
      },
      fieldKeyMap: const {'patchInstallCount': 'patch_install_count'},
    );

Map<String, dynamic> _$AppUsageToJson(AppUsage instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'patch_install_count': instance.patchInstallCount,
    };

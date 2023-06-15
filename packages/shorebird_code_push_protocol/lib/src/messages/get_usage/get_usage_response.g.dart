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
        );
        return val;
      },
    );

Map<String, dynamic> _$GetUsageResponseToJson(GetUsageResponse instance) =>
    <String, dynamic>{
      'apps': instance.apps.map((e) => e.toJson()).toList(),
    };

AppUsage _$AppUsageFromJson(Map<String, dynamic> json) => $checkedCreate(
      'AppUsage',
      json,
      ($checkedConvert) {
        final val = AppUsage(
          id: $checkedConvert('id', (v) => v as String),
          platforms: $checkedConvert(
              'platforms',
              (v) => (v as List<dynamic>)
                  .map((e) => PlatformUsage.fromJson(e as Map<String, dynamic>))
                  .toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$AppUsageToJson(AppUsage instance) => <String, dynamic>{
      'id': instance.id,
      'platforms': instance.platforms.map((e) => e.toJson()).toList(),
    };

PlatformUsage _$PlatformUsageFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'PlatformUsage',
      json,
      ($checkedConvert) {
        final val = PlatformUsage(
          name: $checkedConvert('name', (v) => v as String),
          arches: $checkedConvert(
              'arches',
              (v) => (v as List<dynamic>)
                  .map((e) => ArchUsage.fromJson(e as Map<String, dynamic>))
                  .toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$PlatformUsageToJson(PlatformUsage instance) =>
    <String, dynamic>{
      'name': instance.name,
      'arches': instance.arches.map((e) => e.toJson()).toList(),
    };

ArchUsage _$ArchUsageFromJson(Map<String, dynamic> json) => $checkedCreate(
      'ArchUsage',
      json,
      ($checkedConvert) {
        final val = ArchUsage(
          name: $checkedConvert('name', (v) => v as String),
          patches: $checkedConvert(
              'patches',
              (v) => (v as List<dynamic>)
                  .map((e) => PatchUsage.fromJson(e as Map<String, dynamic>))
                  .toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$ArchUsageToJson(ArchUsage instance) => <String, dynamic>{
      'name': instance.name,
      'patches': instance.patches.map((e) => e.toJson()).toList(),
    };

PatchUsage _$PatchUsageFromJson(Map<String, dynamic> json) => $checkedCreate(
      'PatchUsage',
      json,
      ($checkedConvert) {
        final val = PatchUsage(
          number: $checkedConvert('number', (v) => v as int),
          installCount: $checkedConvert('install_count', (v) => v as int),
        );
        return val;
      },
      fieldKeyMap: const {'installCount': 'install_count'},
    );

Map<String, dynamic> _$PatchUsageToJson(PatchUsage instance) =>
    <String, dynamic>{
      'number': instance.number,
      'install_count': instance.installCount,
    };

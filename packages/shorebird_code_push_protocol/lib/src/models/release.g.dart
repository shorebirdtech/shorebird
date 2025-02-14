// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'release.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Release _$ReleaseFromJson(Map<String, dynamic> json) => $checkedCreate(
  'Release',
  json,
  ($checkedConvert) {
    final val = Release(
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      appId: $checkedConvert('app_id', (v) => v as String),
      version: $checkedConvert('version', (v) => v as String),
      flutterRevision: $checkedConvert('flutter_revision', (v) => v as String),
      flutterVersion: $checkedConvert('flutter_version', (v) => v as String?),
      displayName: $checkedConvert('display_name', (v) => v as String?),
      platformStatuses: $checkedConvert(
        'platform_statuses',
        (v) => (v as Map<String, dynamic>).map(
          (k, e) => MapEntry(
            $enumDecode(_$ReleasePlatformEnumMap, k),
            $enumDecode(_$ReleaseStatusEnumMap, e),
          ),
        ),
      ),
      createdAt: $checkedConvert(
        'created_at',
        (v) => DateTime.parse(v as String),
      ),
      updatedAt: $checkedConvert(
        'updated_at',
        (v) => DateTime.parse(v as String),
      ),
      notes: $checkedConvert('notes', (v) => v as String?),
    );
    return val;
  },
  fieldKeyMap: const {
    'appId': 'app_id',
    'flutterRevision': 'flutter_revision',
    'flutterVersion': 'flutter_version',
    'displayName': 'display_name',
    'platformStatuses': 'platform_statuses',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
);

Map<String, dynamic> _$ReleaseToJson(Release instance) => <String, dynamic>{
  'id': instance.id,
  'app_id': instance.appId,
  'version': instance.version,
  'flutter_revision': instance.flutterRevision,
  'flutter_version': instance.flutterVersion,
  'display_name': instance.displayName,
  'platform_statuses': instance.platformStatuses.map(
    (k, e) =>
        MapEntry(_$ReleasePlatformEnumMap[k]!, _$ReleaseStatusEnumMap[e]!),
  ),
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
  'notes': instance.notes,
};

const _$ReleaseStatusEnumMap = {
  ReleaseStatus.draft: 'draft',
  ReleaseStatus.active: 'active',
};

const _$ReleasePlatformEnumMap = {
  ReleasePlatform.android: 'android',
  ReleasePlatform.ios: 'ios',
  ReleasePlatform.linux: 'linux',
  ReleasePlatform.macos: 'macos',
  ReleasePlatform.windows: 'windows',
};

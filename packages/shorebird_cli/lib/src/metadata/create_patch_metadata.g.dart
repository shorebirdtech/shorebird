// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, strict_raw_type, unnecessary_lambdas

part of 'create_patch_metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreatePatchMetadata _$CreatePatchMetadataFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'CreatePatchMetadata',
  json,
  ($checkedConvert) {
    final val = CreatePatchMetadata(
      releasePlatform: $checkedConvert(
        'release_platform',
        (v) => ReleasePlatform.fromJson(v as String),
      ),
      usedIgnoreAssetChangesFlag: $checkedConvert(
        'used_ignore_asset_changes_flag',
        (v) => v as bool,
      ),
      hasAssetChanges: $checkedConvert('has_asset_changes', (v) => v as bool),
      usedIgnoreNativeChangesFlag: $checkedConvert(
        'used_ignore_native_changes_flag',
        (v) => v as bool,
      ),
      hasNativeChanges: $checkedConvert('has_native_changes', (v) => v as bool),
      environment: $checkedConvert(
        'environment',
        (v) => BuildEnvironmentMetadata.fromJson(v as Map<String, dynamic>),
      ),
      isSigned: $checkedConvert('is_signed', (v) => v as bool),
      usedDefaultTrack: $checkedConvert(
        'used_default_track',
        (v) => v as bool? ?? false,
      ),
      linkPercentage: $checkedConvert(
        'link_percentage',
        (v) => (v as num?)?.toDouble(),
      ),
      linkMetadata: $checkedConvert(
        'link_metadata',
        (v) => v as Map<String, dynamic>?,
      ),
      buildTraceSummary: $checkedConvert(
        'build_trace_summary',
        (v) => v as Map<String, dynamic>?,
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'releasePlatform': 'release_platform',
    'usedIgnoreAssetChangesFlag': 'used_ignore_asset_changes_flag',
    'hasAssetChanges': 'has_asset_changes',
    'usedIgnoreNativeChangesFlag': 'used_ignore_native_changes_flag',
    'hasNativeChanges': 'has_native_changes',
    'isSigned': 'is_signed',
    'usedDefaultTrack': 'used_default_track',
    'linkPercentage': 'link_percentage',
    'linkMetadata': 'link_metadata',
    'buildTraceSummary': 'build_trace_summary',
  },
);

Map<String, dynamic> _$CreatePatchMetadataToJson(
  CreatePatchMetadata instance,
) => <String, dynamic>{
  'release_platform': instance.releasePlatform.toJson(),
  'used_ignore_asset_changes_flag': instance.usedIgnoreAssetChangesFlag,
  'has_asset_changes': instance.hasAssetChanges,
  'used_ignore_native_changes_flag': instance.usedIgnoreNativeChangesFlag,
  'has_native_changes': instance.hasNativeChanges,
  'link_percentage': instance.linkPercentage,
  'link_metadata': instance.linkMetadata,
  'is_signed': instance.isSigned,
  'used_default_track': instance.usedDefaultTrack,
  'environment': instance.environment.toJson(),
  'build_trace_summary': instance.buildTraceSummary,
};

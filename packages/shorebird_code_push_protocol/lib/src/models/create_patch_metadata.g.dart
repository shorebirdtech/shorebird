// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_patch_metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreatePatchMetadata _$CreatePatchMetadataFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CreatePatchMetadata',
      json,
      ($checkedConvert) {
        final val = CreatePatchMetadata(
          releasePlatform: $checkedConvert('release_platform',
              (v) => $enumDecode(_$ReleasePlatformEnumMap, v)),
          usedIgnoreAssetChangesFlag: $checkedConvert(
              'used_ignore_asset_changes_flag', (v) => v as bool),
          hasAssetChanges:
              $checkedConvert('has_asset_changes', (v) => v as bool),
          usedIgnoreNativeChangesFlag: $checkedConvert(
              'used_ignore_native_changes_flag', (v) => v as bool),
          hasNativeChanges:
              $checkedConvert('has_native_changes', (v) => v as bool),
          environment: $checkedConvert(
              'environment',
              (v) =>
                  BuildEnvironmentMetadata.fromJson(v as Map<String, dynamic>)),
          linkPercentage: $checkedConvert(
              'link_percentage', (v) => (v as num?)?.toDouble()),
        );
        return val;
      },
      fieldKeyMap: const {
        'releasePlatform': 'release_platform',
        'usedIgnoreAssetChangesFlag': 'used_ignore_asset_changes_flag',
        'hasAssetChanges': 'has_asset_changes',
        'usedIgnoreNativeChangesFlag': 'used_ignore_native_changes_flag',
        'hasNativeChanges': 'has_native_changes',
        'linkPercentage': 'link_percentage'
      },
    );

Map<String, dynamic> _$CreatePatchMetadataToJson(
        CreatePatchMetadata instance) =>
    <String, dynamic>{
      'release_platform': _$ReleasePlatformEnumMap[instance.releasePlatform]!,
      'used_ignore_asset_changes_flag': instance.usedIgnoreAssetChangesFlag,
      'has_asset_changes': instance.hasAssetChanges,
      'used_ignore_native_changes_flag': instance.usedIgnoreNativeChangesFlag,
      'has_native_changes': instance.hasNativeChanges,
      'link_percentage': instance.linkPercentage,
      'environment': instance.environment.toJson(),
    };

const _$ReleasePlatformEnumMap = {
  ReleasePlatform.android: 'android',
  ReleasePlatform.ios: 'ios',
};

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
        );
        return val;
      },
      fieldKeyMap: const {
        'usedIgnoreAssetChangesFlag': 'used_ignore_asset_changes_flag',
        'hasAssetChanges': 'has_asset_changes',
        'usedIgnoreNativeChangesFlag': 'used_ignore_native_changes_flag',
        'hasNativeChanges': 'has_native_changes'
      },
    );

Map<String, dynamic> _$CreatePatchMetadataToJson(
        CreatePatchMetadata instance) =>
    <String, dynamic>{
      'used_ignore_asset_changes_flag': instance.usedIgnoreAssetChangesFlag,
      'has_asset_changes': instance.hasAssetChanges,
      'used_ignore_native_changes_flag': instance.usedIgnoreNativeChangesFlag,
      'has_native_changes': instance.hasNativeChanges,
      'environment': instance.environment.toJson(),
    };

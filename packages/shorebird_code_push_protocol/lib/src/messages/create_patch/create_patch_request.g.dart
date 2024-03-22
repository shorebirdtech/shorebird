// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_patch_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreatePatchRequest _$CreatePatchRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CreatePatchRequest',
      json,
      ($checkedConvert) {
        final val = CreatePatchRequest(
          releaseId: $checkedConvert('release_id', (v) => v as int),
          wasForced: $checkedConvert('was_forced', (v) => v as bool?),
          hasAssetChanges:
              $checkedConvert('has_asset_changes', (v) => v as bool?),
          hasNativeChanges:
              $checkedConvert('has_native_changes', (v) => v as bool?),
          metadata: $checkedConvert(
              'metadata',
              (v) => v == null
                  ? null
                  : CreatePatchMetadata.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
      fieldKeyMap: const {
        'releaseId': 'release_id',
        'wasForced': 'was_forced',
        'hasAssetChanges': 'has_asset_changes',
        'hasNativeChanges': 'has_native_changes'
      },
    );

Map<String, dynamic> _$CreatePatchRequestToJson(CreatePatchRequest instance) =>
    <String, dynamic>{
      'release_id': instance.releaseId,
      'was_forced': instance.wasForced,
      'has_asset_changes': instance.hasAssetChanges,
      'has_native_changes': instance.hasNativeChanges,
      'metadata': instance.metadata?.toJson(),
    };

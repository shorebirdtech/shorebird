// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'check_for_patches_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$CheckForPatchesResponseToJson(
        CheckForPatchesResponse instance) =>
    <String, dynamic>{
      'patch_available': instance.patchAvailable,
      'patch': instance.patch?.toJson(),
    };

Map<String, dynamic> _$PatchMetadataToJson(PatchMetadata instance) =>
    <String, dynamic>{
      'number': instance.number,
      'download_url': instance.downloadUrl,
      'hash': instance.hash,
    };

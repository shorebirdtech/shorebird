// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'patch_check_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PatchCheckResponse _$PatchCheckResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'PatchCheckResponse',
      json,
      ($checkedConvert) {
        final val = PatchCheckResponse(
          patchAvailable: $checkedConvert('patch_available', (v) => v as bool),
          patch: $checkedConvert(
            'patch',
            (v) => v == null
                ? null
                : PatchCheckMetadata.fromJson(v as Map<String, dynamic>),
          ),
          rolledBackPatchNumbers: $checkedConvert(
            'rolled_back_patch_numbers',
            (v) =>
                (v as List<dynamic>?)?.map((e) => (e as num).toInt()).toList(),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'patchAvailable': 'patch_available',
        'rolledBackPatchNumbers': 'rolled_back_patch_numbers',
      },
    );

Map<String, dynamic> _$PatchCheckResponseToJson(PatchCheckResponse instance) =>
    <String, dynamic>{
      'patch_available': instance.patchAvailable,
      'patch': instance.patch?.toJson(),
      'rolled_back_patch_numbers': instance.rolledBackPatchNumbers,
    };

PatchCheckMetadata _$PatchCheckMetadataFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'PatchCheckMetadata',
      json,
      ($checkedConvert) {
        final val = PatchCheckMetadata(
          number: $checkedConvert('number', (v) => (v as num).toInt()),
          downloadUrl: $checkedConvert('download_url', (v) => v as String),
          hash: $checkedConvert('hash', (v) => v as String),
          hashSignature: $checkedConvert('hash_signature', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {
        'downloadUrl': 'download_url',
        'hashSignature': 'hash_signature',
      },
    );

Map<String, dynamic> _$PatchCheckMetadataToJson(PatchCheckMetadata instance) =>
    <String, dynamic>{
      'number': instance.number,
      'download_url': instance.downloadUrl,
      'hash': instance.hash,
      if (instance.hashSignature case final value?) 'hash_signature': value,
    };

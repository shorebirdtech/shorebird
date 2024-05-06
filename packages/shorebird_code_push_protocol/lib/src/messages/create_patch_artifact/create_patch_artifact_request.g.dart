// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_patch_artifact_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreatePatchArtifactRequest _$CreatePatchArtifactRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CreatePatchArtifactRequest',
      json,
      ($checkedConvert) {
        final val = CreatePatchArtifactRequest(
          arch: $checkedConvert('arch', (v) => v as String),
          platform: $checkedConvert(
              'platform', (v) => $enumDecode(_$ReleasePlatformEnumMap, v)),
          hash: $checkedConvert('hash', (v) => v as String),
          size: $checkedConvert(
              'size', (v) => CreatePatchArtifactRequest._parseStringToInt(v)),
          hashSignature: $checkedConvert('hash_signature', (v) => v as String?),
        );
        return val;
      },
      fieldKeyMap: const {'hashSignature': 'hash_signature'},
    );

Map<String, dynamic> _$CreatePatchArtifactRequestToJson(
        CreatePatchArtifactRequest instance) =>
    <String, dynamic>{
      'arch': instance.arch,
      'platform': _$ReleasePlatformEnumMap[instance.platform]!,
      'hash': instance.hash,
      'hash_signature': instance.hashSignature,
      'size': CreatePatchArtifactRequest._parseIntToString(instance.size),
    };

const _$ReleasePlatformEnumMap = {
  ReleasePlatform.android: 'android',
  ReleasePlatform.ios: 'ios',
};

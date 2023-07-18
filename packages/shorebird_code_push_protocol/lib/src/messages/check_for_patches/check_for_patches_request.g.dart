// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'check_for_patches_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CheckForPatchesRequest _$CheckForPatchesRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CheckForPatchesRequest',
      json,
      ($checkedConvert) {
        final val = CheckForPatchesRequest(
          releaseVersion:
              $checkedConvert('release_version', (v) => v as String),
          patchNumber: $checkedConvert('patch_number', (v) => v as int?),
          patchHash: $checkedConvert('patch_hash', (v) => v as String?),
          platform: $checkedConvert(
              'platform', (v) => $enumDecode(_$ReleasePlatformEnumMap, v)),
          arch: $checkedConvert('arch', (v) => v as String),
          appId: $checkedConvert('app_id', (v) => v as String),
          channel: $checkedConvert('channel', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {
        'releaseVersion': 'release_version',
        'patchNumber': 'patch_number',
        'patchHash': 'patch_hash',
        'appId': 'app_id'
      },
    );

Map<String, dynamic> _$CheckForPatchesRequestToJson(
        CheckForPatchesRequest instance) =>
    <String, dynamic>{
      'release_version': instance.releaseVersion,
      'patch_number': instance.patchNumber,
      'patch_hash': instance.patchHash,
      'platform': _$ReleasePlatformEnumMap[instance.platform]!,
      'arch': instance.arch,
      'app_id': instance.appId,
      'channel': instance.channel,
    };

const _$ReleasePlatformEnumMap = {
  ReleasePlatform.android: 'android',
  ReleasePlatform.ios: 'ios',
};

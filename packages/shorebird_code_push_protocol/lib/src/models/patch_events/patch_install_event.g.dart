// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'patch_install_event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PatchInstallEvent _$PatchInstallEventFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'PatchInstallEvent',
      json,
      ($checkedConvert) {
        final val = PatchInstallEvent(
          clientId: $checkedConvert('client_id', (v) => v as String),
          appId: $checkedConvert('app_id', (v) => v as String),
          releaseVersion:
              $checkedConvert('release_version', (v) => v as String),
          patchNumber: $checkedConvert('patch_number', (v) => v as int),
          platform: $checkedConvert(
              'platform', (v) => $enumDecode(_$ReleasePlatformEnumMap, v)),
          arch: $checkedConvert('arch', (v) => v as String),
          type: $checkedConvert(
              'type', (v) => v as String? ?? PatchInstallEvent.identifier),
        );
        return val;
      },
      fieldKeyMap: const {
        'clientId': 'client_id',
        'appId': 'app_id',
        'releaseVersion': 'release_version',
        'patchNumber': 'patch_number'
      },
    );

Map<String, dynamic> _$PatchInstallEventToJson(PatchInstallEvent instance) =>
    <String, dynamic>{
      'type': instance.type,
      'client_id': instance.clientId,
      'app_id': instance.appId,
      'release_version': instance.releaseVersion,
      'patch_number': instance.patchNumber,
      'platform': _$ReleasePlatformEnumMap[instance.platform]!,
      'arch': instance.arch,
    };

const _$ReleasePlatformEnumMap = {
  ReleasePlatform.android: 'android',
  ReleasePlatform.ios: 'ios',
};

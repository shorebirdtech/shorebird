// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'record_patch_install_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RecordPatchInstallRequest _$RecordPatchInstallRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'RecordPatchInstallRequest',
      json,
      ($checkedConvert) {
        final val = RecordPatchInstallRequest(
          clientId: $checkedConvert('client_id', (v) => v as String),
          appId: $checkedConvert('app_id', (v) => v as String),
          patchNumber: $checkedConvert('patch_number', (v) => v as int),
        );
        return val;
      },
      fieldKeyMap: const {
        'clientId': 'client_id',
        'appId': 'app_id',
        'patchNumber': 'patch_number'
      },
    );

Map<String, dynamic> _$RecordPatchInstallRequestToJson(
        RecordPatchInstallRequest instance) =>
    <String, dynamic>{
      'client_id': instance.clientId,
      'app_id': instance.appId,
      'patch_number': instance.patchNumber,
    };

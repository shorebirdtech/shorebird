// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_patch_install_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreatePatchInstallRequest _$CreatePatchInstallRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CreatePatchInstallRequest',
      json,
      ($checkedConvert) {
        final val = CreatePatchInstallRequest(
          clientId: $checkedConvert('client_id', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'clientId': 'client_id'},
    );

Map<String, dynamic> _$CreatePatchInstallRequestToJson(
        CreatePatchInstallRequest instance) =>
    <String, dynamic>{
      'client_id': instance.clientId,
    };

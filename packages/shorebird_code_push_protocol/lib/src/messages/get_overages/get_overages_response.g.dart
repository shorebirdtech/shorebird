// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'get_overages_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetOveragesResponse _$GetOveragesResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'GetOveragesResponse',
      json,
      ($checkedConvert) {
        final val = GetOveragesResponse(
          patchInstallOverageLimit:
              $checkedConvert('patch_install_overage_limit', (v) => v as int?),
        );
        return val;
      },
      fieldKeyMap: const {
        'patchInstallOverageLimit': 'patch_install_overage_limit'
      },
    );

Map<String, dynamic> _$GetOveragesResponseToJson(
        GetOveragesResponse instance) =>
    <String, dynamic>{
      'patch_install_overage_limit': instance.patchInstallOverageLimit,
    };

// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'update_overages_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdateOveragesRequest _$UpdateOveragesRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'UpdateOveragesRequest',
      json,
      ($checkedConvert) {
        final val = UpdateOveragesRequest(
          patchInstallOverageLimit:
              $checkedConvert('patch_install_overage_limit', (v) => v as int?),
        );
        return val;
      },
      fieldKeyMap: const {
        'patchInstallOverageLimit': 'patch_install_overage_limit'
      },
    );

Map<String, dynamic> _$UpdateOveragesRequestToJson(
        UpdateOveragesRequest instance) =>
    <String, dynamic>{
      'patch_install_overage_limit': instance.patchInstallOverageLimit,
    };

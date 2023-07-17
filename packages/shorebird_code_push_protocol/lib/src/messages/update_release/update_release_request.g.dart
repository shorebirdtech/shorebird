// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'update_release_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdateReleaseRequest _$UpdateReleaseRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'UpdateReleaseRequest',
      json,
      ($checkedConvert) {
        final val = UpdateReleaseRequest(
          status: $checkedConvert(
              'status', (v) => $enumDecode(_$ReleaseStatusEnumMap, v)),
          platform: $checkedConvert('platform', (v) => v as String),
        );
        return val;
      },
    );

Map<String, dynamic> _$UpdateReleaseRequestToJson(
        UpdateReleaseRequest instance) =>
    <String, dynamic>{
      'status': _$ReleaseStatusEnumMap[instance.status]!,
      'platform': instance.platform,
    };

const _$ReleaseStatusEnumMap = {
  ReleaseStatus.draft: 'draft',
  ReleaseStatus.active: 'active',
};

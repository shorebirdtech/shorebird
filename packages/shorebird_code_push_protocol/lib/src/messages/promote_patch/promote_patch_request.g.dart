// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'promote_patch_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PromotePatchRequest _$PromotePatchRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'PromotePatchRequest',
      json,
      ($checkedConvert) {
        final val = PromotePatchRequest(
          patchId: $checkedConvert('patch_id', (v) => v as int),
          channelId: $checkedConvert('channel_id', (v) => v as int),
        );
        return val;
      },
      fieldKeyMap: const {'patchId': 'patch_id', 'channelId': 'channel_id'},
    );

Map<String, dynamic> _$PromotePatchRequestToJson(
        PromotePatchRequest instance) =>
    <String, dynamic>{
      'patch_id': instance.patchId,
      'channel_id': instance.channelId,
    };

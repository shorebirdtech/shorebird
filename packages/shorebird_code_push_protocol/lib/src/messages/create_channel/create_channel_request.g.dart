// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_channel_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreateChannelRequest _$CreateChannelRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CreateChannelRequest',
      json,
      ($checkedConvert) {
        final val = CreateChannelRequest(
          channel: $checkedConvert('channel', (v) => v as String),
        );
        return val;
      },
    );

Map<String, dynamic> _$CreateChannelRequestToJson(
        CreateChannelRequest instance) =>
    <String, dynamic>{
      'channel': instance.channel,
    };

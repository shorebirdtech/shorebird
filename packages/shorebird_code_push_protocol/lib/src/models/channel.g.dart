// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'channel.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Channel _$ChannelFromJson(Map<String, dynamic> json) => $checkedCreate(
      'Channel',
      json,
      ($checkedConvert) {
        final val = Channel(
          id: $checkedConvert('id', (v) => (v as num).toInt()),
          appId: $checkedConvert('app_id', (v) => v as String),
          name: $checkedConvert('name', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'appId': 'app_id'},
    );

Map<String, dynamic> _$ChannelToJson(Channel instance) => <String, dynamic>{
      'id': instance.id,
      'app_id': instance.appId,
      'name': instance.name,
    };

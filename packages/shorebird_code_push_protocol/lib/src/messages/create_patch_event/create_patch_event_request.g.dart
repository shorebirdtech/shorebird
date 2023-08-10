// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_patch_event_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreatePatchEventRequest _$CreatePatchEventRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CreatePatchEventRequest',
      json,
      ($checkedConvert) {
        final val = CreatePatchEventRequest(
          event: $checkedConvert(
              'event', (v) => PatchEvent.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
    );

Map<String, dynamic> _$CreatePatchEventRequestToJson(
        CreatePatchEventRequest instance) =>
    <String, dynamic>{
      'event': instance.event.toJson(),
    };

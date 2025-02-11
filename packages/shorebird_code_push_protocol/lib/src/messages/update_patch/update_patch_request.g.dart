// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'update_patch_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdatePatchRequest _$UpdatePatchRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'UpdatePatchRequest',
      json,
      ($checkedConvert) {
        final val = UpdatePatchRequest(
          notes: $checkedConvert('notes', (v) => v as String?),
        );
        return val;
      },
    );

Map<String, dynamic> _$UpdatePatchRequestToJson(UpdatePatchRequest instance) =>
    <String, dynamic>{
      'notes': instance.notes,
    };

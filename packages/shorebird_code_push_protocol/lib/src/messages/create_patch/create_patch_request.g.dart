// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_patch_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreatePatchRequest _$CreatePatchRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CreatePatchRequest',
      json,
      ($checkedConvert) {
        final val = CreatePatchRequest(
          releaseId: $checkedConvert('release_id', (v) => v as int),
        );
        return val;
      },
      fieldKeyMap: const {'releaseId': 'release_id'},
    );

Map<String, dynamic> _$CreatePatchRequestToJson(CreatePatchRequest instance) =>
    <String, dynamic>{
      'release_id': instance.releaseId,
    };

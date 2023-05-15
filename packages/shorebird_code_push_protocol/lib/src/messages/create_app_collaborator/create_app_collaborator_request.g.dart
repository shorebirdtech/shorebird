// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'create_app_collaborator_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreateAppCollaboratorRequest _$CreateAppCollaboratorRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'CreateAppCollaboratorRequest',
      json,
      ($checkedConvert) {
        final val = CreateAppCollaboratorRequest(
          userId: $checkedConvert('user_id', (v) => v as int),
        );
        return val;
      },
      fieldKeyMap: const {'userId': 'user_id'},
    );

Map<String, dynamic> _$CreateAppCollaboratorRequestToJson(
        CreateAppCollaboratorRequest instance) =>
    <String, dynamic>{
      'user_id': instance.userId,
    };

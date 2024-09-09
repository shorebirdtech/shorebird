// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'update_app_collaborator_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdateAppCollaboratorRequest _$UpdateAppCollaboratorRequestFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'UpdateAppCollaboratorRequest',
      json,
      ($checkedConvert) {
        final val = UpdateAppCollaboratorRequest(
          role: $checkedConvert(
              'role', (v) => $enumDecode(_$AppCollaboratorRoleEnumMap, v)),
        );
        return val;
      },
    );

Map<String, dynamic> _$UpdateAppCollaboratorRequestToJson(
        UpdateAppCollaboratorRequest instance) =>
    <String, dynamic>{
      'role': _$AppCollaboratorRoleEnumMap[instance.role]!,
    };

const _$AppCollaboratorRoleEnumMap = {
  AppCollaboratorRole.admin: 'admin',
  AppCollaboratorRole.developer: 'developer',
};

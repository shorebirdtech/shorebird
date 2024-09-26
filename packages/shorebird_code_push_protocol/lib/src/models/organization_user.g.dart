// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'organization_user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OrganizationUser _$OrganizationUserFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'OrganizationUser',
      json,
      ($checkedConvert) {
        final val = OrganizationUser(
          user: $checkedConvert(
              'user', (v) => User.fromJson(v as Map<String, dynamic>)),
          role: $checkedConvert(
              'role', (v) => $enumDecode(_$OrganizationRoleEnumMap, v)),
        );
        return val;
      },
    );

Map<String, dynamic> _$OrganizationUserToJson(OrganizationUser instance) =>
    <String, dynamic>{
      'user': instance.user.toJson(),
      'role': _$OrganizationRoleEnumMap[instance.role]!,
    };

const _$OrganizationRoleEnumMap = {
  OrganizationRole.owner: 'owner',
  OrganizationRole.admin: 'admin',
  OrganizationRole.member: 'member',
};

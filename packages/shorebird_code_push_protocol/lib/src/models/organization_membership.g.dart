// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'organization_membership.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OrganizationMembership _$OrganizationMembershipFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'OrganizationMembership',
      json,
      ($checkedConvert) {
        final val = OrganizationMembership(
          organization: $checkedConvert('organization',
              (v) => Organization.fromJson(v as Map<String, dynamic>)),
          role: $checkedConvert(
              'role', (v) => $enumDecode(_$OrganizationRoleEnumMap, v)),
        );
        return val;
      },
    );

Map<String, dynamic> _$OrganizationMembershipToJson(
        OrganizationMembership instance) =>
    <String, dynamic>{
      'organization': instance.organization.toJson(),
      'role': _$OrganizationRoleEnumMap[instance.role]!,
    };

const _$OrganizationRoleEnumMap = {
  OrganizationRole.owner: 'owner',
  OrganizationRole.admin: 'admin',
  OrganizationRole.member: 'member',
};

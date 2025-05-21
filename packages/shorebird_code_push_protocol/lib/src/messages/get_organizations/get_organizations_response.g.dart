// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'get_organizations_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetOrganizationsResponse _$GetOrganizationsResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('GetOrganizationsResponse', json, ($checkedConvert) {
  final val = GetOrganizationsResponse(
    organizations: $checkedConvert(
      'organizations',
      (v) => (v as List<dynamic>)
          .map(
            (e) => OrganizationMembership.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    ),
  );
  return val;
});

Map<String, dynamic> _$GetOrganizationsResponseToJson(
  GetOrganizationsResponse instance,
) => <String, dynamic>{
  'organizations': instance.organizations.map((e) => e.toJson()).toList(),
};

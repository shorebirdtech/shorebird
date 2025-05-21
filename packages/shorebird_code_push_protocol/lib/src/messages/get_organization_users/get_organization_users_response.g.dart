// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars

part of 'get_organization_users_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetOrganizationUsersResponse _$GetOrganizationUsersResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('GetOrganizationUsersResponse', json, ($checkedConvert) {
  final val = GetOrganizationUsersResponse(
    users: $checkedConvert(
      'users',
      (v) => (v as List<dynamic>)
          .map((e) => OrganizationUser.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
  );
  return val;
});

Map<String, dynamic> _$GetOrganizationUsersResponseToJson(
  GetOrganizationUsersResponse instance,
) => <String, dynamic>{'users': instance.users.map((e) => e.toJson()).toList()};

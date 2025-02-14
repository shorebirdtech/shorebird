import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/src/models/models.dart';

part 'get_organization_users_response.g.dart';

/// {@template get_organization_users_request}
/// A list of users that belong to an organization, as well as their roles in
/// the organization.
///
/// The body of GET /api/v1/organizations/:organizationId/users
/// {@endtemplate}
@JsonSerializable()
class GetOrganizationUsersResponse {
  /// {@macro get_organization_users_request}
  GetOrganizationUsersResponse({required this.users});

  /// Deserializes the [GetOrganizationUsersResponse] from a JSON map.
  factory GetOrganizationUsersResponse.fromJson(Map<String, dynamic> json) =>
      _$GetOrganizationUsersResponseFromJson(json);

  /// Converts this [GetOrganizationUsersResponse] to a JSON map.
  Map<String, dynamic> toJson() => _$GetOrganizationUsersResponseToJson(this);

  /// The list of users that belong to the organization, as well as their roles
  /// in the organization.
  final List<OrganizationUser> users;
}

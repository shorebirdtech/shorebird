import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'get_organizations_response.g.dart';

/// {@template get_organizations_request}
/// A list of organizations the currently logged in user is a member of.
///
/// Body of /api/v1/organizations.
/// {@endtemplate}
@JsonSerializable()
class GetOrganizationsResponse {
  /// {@macro get_organizations_request}
  GetOrganizationsResponse({
    required this.organizations,
  });

  /// Deserializes the [GetOrganizationsResponse] from a JSON map.
  factory GetOrganizationsResponse.fromJson(Map<String, dynamic> json) =>
      _$GetOrganizationsResponseFromJson(json);

  /// Converts this [GetOrganizationsResponse] to a JSON map.
  Map<String, dynamic> toJson() => _$GetOrganizationsResponseToJson(this);

  /// Organizations that the user is a member of, as well as this user's role in
  /// each organization.
  final List<OrganizationMembership> organizations;
}

import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'get_organization_apps_response.g.dart';

/// {@template get_organization_apps_request}
/// A list of apps that belong to an organization.
///
/// Body of GET /api/v1/organizations/:organizationId/apps
/// {@endtemplate}
@JsonSerializable()
class GetOrganizationAppsResponse {
  /// {@macro get_organization_apps_request}
  GetOrganizationAppsResponse({
    required this.apps,
  });

  /// Deserializes the [GetOrganizationAppsResponse] from a JSON map.
  factory GetOrganizationAppsResponse.fromJson(Map<String, dynamic> json) =>
      _$GetOrganizationAppsResponseFromJson(json);

  /// Converts this [GetOrganizationAppsResponse] to a JSON map.
  Map<String, dynamic> toJson() => _$GetOrganizationAppsResponseToJson(this);

  /// The apps that belong to the organization.
  final List<AppMetadata> apps;
}

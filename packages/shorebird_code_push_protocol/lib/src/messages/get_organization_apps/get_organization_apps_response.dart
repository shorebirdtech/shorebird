import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/app_metadata.dart';

/// {@template get_organization_apps_response}
/// The response body for GET /organizations/{organizationId}/apps.
/// {@endtemplate}
@immutable
class GetOrganizationAppsResponse {
  /// {@macro get_organization_apps_response}
  const GetOrganizationAppsResponse({
    required this.apps,
  });

  /// Converts a `Map<String, dynamic>` to a [GetOrganizationAppsResponse].
  factory GetOrganizationAppsResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetOrganizationAppsResponse',
      json,
      () => GetOrganizationAppsResponse(
        apps: (json['apps'] as List)
            .map<AppMetadata>(
              (e) => AppMetadata.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetOrganizationAppsResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetOrganizationAppsResponse.fromJson(json);
  }

  /// The apps that belong to the organization.
  final List<AppMetadata> apps;

  /// Converts a [GetOrganizationAppsResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'apps': apps.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => listHash(apps).hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetOrganizationAppsResponse && listsEqual(apps, other.apps);
  }
}

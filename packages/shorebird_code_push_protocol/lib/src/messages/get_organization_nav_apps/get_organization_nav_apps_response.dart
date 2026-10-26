import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/nav_app.dart';

/// {@template get_organization_nav_apps_response}
/// The response body for GET /organizations/{organizationId}/apps/nav.
/// {@endtemplate}
@immutable
class GetOrganizationNavAppsResponse {
  /// {@macro get_organization_nav_apps_response}
  const GetOrganizationNavAppsResponse({
    required this.apps,
  });

  /// Converts a `Map<String, dynamic>` to a [GetOrganizationNavAppsResponse].
  factory GetOrganizationNavAppsResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetOrganizationNavAppsResponse',
      json,
      () => GetOrganizationNavAppsResponse(
        apps: (json['apps'] as List)
            .map<NavApp>((e) => NavApp.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetOrganizationNavAppsResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetOrganizationNavAppsResponse.fromJson(json);
  }

  /// Up to 10 apps: those named in `ids` first, then the rest most
  /// recently updated first.
  final List<NavApp> apps;

  /// Converts a [GetOrganizationNavAppsResponse] to a `Map<String, dynamic>`.
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
    return other is GetOrganizationNavAppsResponse &&
        listsEqual(apps, other.apps);
  }
}

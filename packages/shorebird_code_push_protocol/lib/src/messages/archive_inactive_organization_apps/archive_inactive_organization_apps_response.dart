import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template archive_inactive_organization_apps_response}
/// The response body for
/// POST /organizations/{organizationId}/apps/archive-inactive.
/// {@endtemplate}
@immutable
class ArchiveInactiveOrganizationAppsResponse {
  /// {@macro archive_inactive_organization_apps_response}
  const ArchiveInactiveOrganizationAppsResponse({
    required this.archivedAppIds,
  });

  /// Converts a `Map<String, dynamic>` to an
  /// [ArchiveInactiveOrganizationAppsResponse].
  factory ArchiveInactiveOrganizationAppsResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'ArchiveInactiveOrganizationAppsResponse',
      json,
      () => ArchiveInactiveOrganizationAppsResponse(
        archivedAppIds: (json['archived_app_ids'] as List).cast<String>(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ArchiveInactiveOrganizationAppsResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return ArchiveInactiveOrganizationAppsResponse.fromJson(json);
  }

  /// The IDs of the apps the request archived.
  final List<String> archivedAppIds;

  /// Converts an [ArchiveInactiveOrganizationAppsResponse]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'archived_app_ids': archivedAppIds,
    };
  }

  @override
  int get hashCode => listHash(archivedAppIds).hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ArchiveInactiveOrganizationAppsResponse &&
        listsEqual(archivedAppIds, other.archivedAppIds);
  }
}

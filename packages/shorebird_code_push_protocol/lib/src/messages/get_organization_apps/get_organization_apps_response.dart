import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/app_metadata.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template get_organization_apps_response}
/// The response body for GET /organizations/{organizationId}/apps.
/// {@endtemplate}
@immutable
class GetOrganizationAppsResponse {
  /// {@macro get_organization_apps_response}
  const GetOrganizationAppsResponse({
    required this.apps,
    this.nextCursor,
    this.totalCount,
    this.platforms,
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
        nextCursor: json['next_cursor'] as String?,
        totalCount: json['total_count'] as int?,
        platforms: (json['platforms'] as List?)
            ?.map<ReleasePlatform>((e) => ReleasePlatform.fromJson(e as String))
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

  /// The opaque cursor of the next page; send it back as `cursor`
  /// to get that page.
  /// Present only when the request was paginated (sent `per_page`,
  /// `cursor` or `page`) and another page follows. Absent on the last
  /// page and on unpaginated responses.
  final String? nextCursor;

  /// How many items the whole list holds. Present only when the
  /// request was paginated.
  final int? totalCount;

  /// The platforms the listed apps have a release on, across every app
  /// the caller may see in the organization, whatever `q` and
  /// `platform` narrowed the page to. Present only when the request
  /// was paginated.
  final List<ReleasePlatform>? platforms;

  /// Converts a [GetOrganizationAppsResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'apps': apps.map((e) => e.toJson()).toList(),
      'next_cursor': ?nextCursor,
      'total_count': ?totalCount,
      'platforms': ?platforms?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(apps),
    nextCursor,
    totalCount,
    listHash(platforms),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetOrganizationAppsResponse &&
        listsEqual(apps, other.apps) &&
        nextCursor == other.nextCursor &&
        totalCount == other.totalCount &&
        listsEqual(platforms, other.platforms);
  }
}

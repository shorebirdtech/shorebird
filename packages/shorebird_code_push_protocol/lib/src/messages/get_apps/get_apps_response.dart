import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/app_metadata.dart';

/// {@template get_apps_response}
/// The response body for GET /apps.
/// {@endtemplate}
@immutable
class GetAppsResponse {
  /// {@macro get_apps_response}
  const GetAppsResponse({
    required this.apps,
    this.nextCursor,
  });

  /// Converts a `Map<String, dynamic>` to a [GetAppsResponse].
  factory GetAppsResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetAppsResponse',
      json,
      () => GetAppsResponse(
        apps: (json['apps'] as List)
            .map<AppMetadata>(
              (e) => AppMetadata.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        nextCursor: json['next_cursor'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetAppsResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetAppsResponse.fromJson(json);
  }

  /// The list of apps.
  final List<AppMetadata> apps;

  /// The opaque cursor of the next page; send it back as `cursor`
  /// to get that page.
  /// Present only when the request was paginated (sent `per_page` or
  /// `cursor`) and another page follows. Absent on the last page and
  /// on unpaginated responses.
  final String? nextCursor;

  /// Converts a [GetAppsResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'apps': apps.map((e) => e.toJson()).toList(),
      'next_cursor': ?nextCursor,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(apps),
    nextCursor,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetAppsResponse &&
        listsEqual(apps, other.apps) &&
        nextCursor == other.nextCursor;
  }
}

import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release.dart';

/// {@template get_releases_response}
/// The response body for GET /apps/{appId}/releases.
/// {@endtemplate}
@immutable
class GetReleasesResponse {
  /// {@macro get_releases_response}
  const GetReleasesResponse({
    required this.releases,
    this.nextCursor,
  });

  /// Converts a `Map<String, dynamic>` to a [GetReleasesResponse].
  factory GetReleasesResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetReleasesResponse',
      json,
      () => GetReleasesResponse(
        releases: (json['releases'] as List)
            .map<Release>((e) => Release.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextCursor: json['next_cursor'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetReleasesResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetReleasesResponse.fromJson(json);
  }

  /// The list of releases for the app.
  final List<Release> releases;

  /// The opaque cursor of the next page; send it back as `cursor`
  /// to get that page.
  /// Present only when the request was paginated (sent `per_page` or
  /// `cursor`) and another page follows. Absent on the last page and
  /// on unpaginated responses.
  final String? nextCursor;

  /// Converts a [GetReleasesResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'releases': releases.map((e) => e.toJson()).toList(),
      'next_cursor': ?nextCursor,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(releases),
    nextCursor,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetReleasesResponse &&
        listsEqual(releases, other.releases) &&
        nextCursor == other.nextCursor;
  }
}

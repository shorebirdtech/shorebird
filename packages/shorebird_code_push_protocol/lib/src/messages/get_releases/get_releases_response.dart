// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
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

  /// Converts a [GetReleasesResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'releases': releases.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => listHash(releases).hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetReleasesResponse && listsEqual(releases, other.releases);
  }
}

// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release.dart';

/// {@template get_release_response}
/// The response body for GET /apps/{appId}/releases/{releaseId}.
/// {@endtemplate}
@immutable
class GetReleaseResponse {
  /// {@macro get_release_response}
  const GetReleaseResponse({
    required this.release,
  });

  /// Converts a `Map<String, dynamic>` to a [GetReleaseResponse].
  factory GetReleaseResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetReleaseResponse',
      json,
      () => GetReleaseResponse(
        release: Release.fromJson(json['release'] as Map<String, dynamic>),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetReleaseResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetReleaseResponse.fromJson(json);
  }

  /// A release build of an application that is distributed to devices.
  /// A release can have zero or more patches applied to it.
  final Release release;

  /// Converts a [GetReleaseResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'release': release.toJson(),
    };
  }

  @override
  int get hashCode => release.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetReleaseResponse && release == other.release;
  }
}

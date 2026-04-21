import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release.dart';

/// {@template create_release_response}
/// The response body for POST /apps/{appId}/releases.
/// {@endtemplate}
@immutable
class CreateReleaseResponse {
  /// {@macro create_release_response}
  const CreateReleaseResponse({
    required this.release,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateReleaseResponse].
  factory CreateReleaseResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateReleaseResponse',
      json,
      () => CreateReleaseResponse(
        release: Release.fromJson(json['release'] as Map<String, dynamic>),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateReleaseResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreateReleaseResponse.fromJson(json);
  }

  /// A release build of an application that is distributed to devices.
  /// A release can have zero or more patches applied to it.
  final Release release;

  /// Converts a [CreateReleaseResponse] to a `Map<String, dynamic>`.
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
    return other is CreateReleaseResponse && release == other.release;
  }
}

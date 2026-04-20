import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template create_release_request}
/// The request body for POST /apps/{appId}/releases.
/// {@endtemplate}
@immutable
class CreateReleaseRequest {
  /// {@macro create_release_request}
  const CreateReleaseRequest({
    required this.version,
    required this.flutterRevision,
    this.flutterVersion,
    this.displayName,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateReleaseRequest].
  factory CreateReleaseRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateReleaseRequest',
      json,
      () => CreateReleaseRequest(
        version: json['version'] as String,
        flutterRevision: json['flutter_revision'] as String,
        flutterVersion: json['flutter_version'] as String?,
        displayName: json['display_name'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateReleaseRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreateReleaseRequest.fromJson(json);
  }

  /// The release version.
  final String version;

  /// The Flutter revision used to create the release.
  final String flutterRevision;

  /// The Flutter version used to create the release.  This field is optional
  /// because it was newly added and older releases do not have this
  /// information.
  final String? flutterVersion;

  /// The display name for the release.
  final String? displayName;

  /// Converts a [CreateReleaseRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'flutter_revision': flutterRevision,
      'flutter_version': flutterVersion,
      'display_name': displayName,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    version,
    flutterRevision,
    flutterVersion,
    displayName,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateReleaseRequest &&
        version == other.version &&
        flutterRevision == other.flutterRevision &&
        flutterVersion == other.flutterVersion &&
        displayName == other.displayName;
  }
}

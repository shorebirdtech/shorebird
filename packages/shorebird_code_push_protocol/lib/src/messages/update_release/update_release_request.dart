// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';
import 'package:shorebird_code_push_protocol/src/models/release_status.dart';

/// {@template update_release_request}
/// The request body for PATCH /apps/{appId}/releases/{releaseId}.
/// {@endtemplate}
@immutable
class UpdateReleaseRequest {
  /// {@macro update_release_request}
  const UpdateReleaseRequest({
    this.status,
    this.platform,
    this.metadata,
    this.notes,
  });

  /// Converts a `Map<String, dynamic>` to a [UpdateReleaseRequest].
  factory UpdateReleaseRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'UpdateReleaseRequest',
      json,
      () => UpdateReleaseRequest(
        status: ReleaseStatus.maybeFromJson(json['status'] as String?),
        platform: ReleasePlatform.maybeFromJson(json['platform'] as String?),
        metadata: (json['metadata'] as Map<String, dynamic>?)?.map(
          MapEntry.new,
        ),
        notes: json['notes'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static UpdateReleaseRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return UpdateReleaseRequest.fromJson(json);
  }

  /// The status of a release.
  final ReleaseStatus? status;

  /// A platform to which a Shorebird release can be deployed.
  final ReleasePlatform? platform;

  /// Additional information about the command that was run to
  /// update the release and the environment it was run in.
  final Map<String, dynamic>? metadata;

  /// Notes about the release. This is a free-form field that can be used to
  /// store additional information about the release. If null, the notes will
  /// not be updated.
  final String? notes;

  /// Converts a [UpdateReleaseRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'status': status?.toJson(),
      'platform': platform?.toJson(),
      'metadata': metadata,
      'notes': notes,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    status,
    platform,
    mapHash(metadata),
    notes,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UpdateReleaseRequest &&
        status == other.status &&
        platform == other.platform &&
        mapsEqual(metadata, other.metadata) &&
        notes == other.notes;
  }
}

import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_signing_mode.dart';

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
    this.signingMode,
    this.signingKeyId,
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
        signingMode: ReleaseSigningMode.maybeFromJson(
          json['signing_mode'] as String?,
        ),
        signingKeyId: json['signing_key_id'] as int?,
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

  /// How a release's binaries were signed for patch signing.
  final ReleaseSigningMode? signingMode;

  /// The managed key the CLI embedded, as GET
  /// /apps/{appId}/signing-key returned it. Required when
  /// signing_mode is managed, and refused otherwise.
  final int? signingKeyId;

  /// Converts a [CreateReleaseRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'flutter_revision': flutterRevision,
      'flutter_version': ?flutterVersion,
      'display_name': ?displayName,
      'signing_mode': ?signingMode?.toJson(),
      'signing_key_id': ?signingKeyId,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    version,
    flutterRevision,
    flutterVersion,
    displayName,
    signingMode,
    signingKeyId,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateReleaseRequest &&
        version == other.version &&
        flutterRevision == other.flutterRevision &&
        flutterVersion == other.flutterVersion &&
        displayName == other.displayName &&
        signingMode == other.signingMode &&
        signingKeyId == other.signingKeyId;
  }
}

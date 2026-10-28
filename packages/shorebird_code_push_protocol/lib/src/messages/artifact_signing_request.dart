import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_signing_mode.dart';

/// {@template artifact_signing_request}
/// How the CLI signed a release artifact's binary. A managed binary
/// names the key GET /apps/{appId}/signing-key returned (key_id). A
/// customer-signed or unsigned binary sends only its mode.
/// {@endtemplate}
@immutable
class ArtifactSigningRequest {
  /// {@macro artifact_signing_request}
  const ArtifactSigningRequest({
    required this.mode,
    this.keyId,
  });

  /// Converts a `Map<String, dynamic>` to an [ArtifactSigningRequest].
  factory ArtifactSigningRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ArtifactSigningRequest',
      json,
      () => ArtifactSigningRequest(
        mode: ReleaseSigningMode.fromJson(json['mode'] as String),
        keyId: json['key_id'] as int?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ArtifactSigningRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ArtifactSigningRequest.fromJson(json);
  }

  /// How a release artifact's binary is signed for patch signing.
  final ReleaseSigningMode mode;

  /// The managed key the binary embeds. Required when mode is
  /// managed, and refused otherwise.
  final int? keyId;

  /// Converts an [ArtifactSigningRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'mode': mode.toJson(),
      'key_id': ?keyId,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    mode,
    keyId,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ArtifactSigningRequest &&
        mode == other.mode &&
        keyId == other.keyId;
  }
}

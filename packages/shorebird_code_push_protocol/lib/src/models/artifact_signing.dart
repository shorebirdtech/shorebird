import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template artifact_signing}
/// How a release artifact's binary is signed for patch signing: which
/// public key the binary embeds. Patches to that release, platform and
/// arch are verified with it.
/// {@endtemplate}
@immutable
class ArtifactSigning {
  /// {@macro artifact_signing}
  const ArtifactSigning({
    required this.mode,
    this.keyId,
    this.publicKeyPem,
  });

  /// Converts a `Map<String, dynamic>` to an [ArtifactSigning].
  factory ArtifactSigning.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ArtifactSigning',
      json,
      () => ArtifactSigning(
        mode: json['mode'] as String,
        keyId: json['key_id'] as int?,
        publicKeyPem: json['public_key_pem'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ArtifactSigning? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ArtifactSigning.fromJson(json);
  }

  /// One of the ReleaseSigningMode values: managed, customer or
  /// unsigned. A string rather than the enum so that a client meeting
  /// a mode added after it was built reads it as unknown instead of
  /// failing to read the artifact.
  final String mode;

  /// The managed key the binary embeds. Present exactly when mode is
  /// managed.
  final int? keyId;

  /// The public key the binary embeds, PEM encoded
  /// (SubjectPublicKeyInfo): Shorebird's for a managed artifact, the
  /// customer's for a customer one. `shorebird patch` builds and
  /// signs against it. Absent when mode is unsigned.
  final String? publicKeyPem;

  /// Converts an [ArtifactSigning] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'mode': mode,
      'key_id': ?keyId,
      'public_key_pem': ?publicKeyPem,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    mode,
    keyId,
    publicKeyPem,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ArtifactSigning &&
        mode == other.mode &&
        keyId == other.keyId &&
        publicKeyPem == other.publicKeyPem;
  }
}

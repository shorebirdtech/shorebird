import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template release_signing}
/// How a release's binaries are signed for patch signing. Set by the
/// release's first platform; every later platform matches it.
/// {@endtemplate}
@immutable
class ReleaseSigning {
  /// {@macro release_signing}
  const ReleaseSigning({
    required this.mode,
    this.keyId,
    this.publicKeyPem,
  });

  /// Converts a `Map<String, dynamic>` to a [ReleaseSigning].
  factory ReleaseSigning.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ReleaseSigning',
      json,
      () => ReleaseSigning(
        mode: json['mode'] as String,
        keyId: json['key_id'] as int?,
        publicKeyPem: json['public_key_pem'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ReleaseSigning? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ReleaseSigning.fromJson(json);
  }

  /// One of the ReleaseSigningMode values: managed, customer or
  /// unsigned. A string rather than the enum so that a client meeting
  /// a mode added after it was built reads it as unknown instead of
  /// failing to read the release.
  final String mode;

  /// The managed key the release embeds. Present exactly when mode is
  /// managed.
  final int? keyId;

  /// The public key the release embeds, PEM encoded
  /// (SubjectPublicKeyInfo): Shorebird's for a managed release, the
  /// customer's for a customer one. `shorebird patch` and the
  /// release's later platforms build against it. Absent when mode is
  /// unsigned.
  final String? publicKeyPem;

  /// Converts a [ReleaseSigning] to a `Map<String, dynamic>`.
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
    return other is ReleaseSigning &&
        mode == other.mode &&
        keyId == other.keyId &&
        publicKeyPem == other.publicKeyPem;
  }
}

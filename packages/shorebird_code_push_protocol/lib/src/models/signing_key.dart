import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template signing_key}
/// A managed patch-signing key: a key Shorebird holds, whose private
/// half never leaves Cloud KMS, and which signs the patches of every
/// release that embeds it.
/// {@endtemplate}
@immutable
class SigningKey {
  /// {@macro signing_key}
  const SigningKey({
    required this.id,
    required this.publicKeyPem,
  });

  /// Converts a `Map<String, dynamic>` to a [SigningKey].
  factory SigningKey.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'SigningKey',
      json,
      () => SigningKey(
        id: json['id'] as int,
        publicKeyPem: json['public_key_pem'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static SigningKey? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return SigningKey.fromJson(json);
  }

  /// The key's id, which a managed release names as signing.key_id.
  final int id;

  /// The public key, PEM encoded (SubjectPublicKeyInfo), which a
  /// release build embeds to verify its patches.
  final String publicKeyPem;

  /// Converts a [SigningKey] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'public_key_pem': publicKeyPem,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    publicKeyPem,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SigningKey &&
        id == other.id &&
        publicKeyPem == other.publicKeyPem;
  }
}

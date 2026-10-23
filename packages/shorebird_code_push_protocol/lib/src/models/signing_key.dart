import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template signing_key}
/// The public half of a managed patch-signing key. Its private half
/// is held in Cloud KMS and never leaves it.
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

  /// The id a release that embeds the key records.
  final int id;

  /// The RSA public key, PEM encoded.
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

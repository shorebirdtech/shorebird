import 'package:json_annotation/json_annotation.dart';

part 'rsa_jwk.g.dart';

/// {@template rsa_jwk}
/// An RSA JSON Web Key (JWK) as produced by Shorebird's auth service.
///
/// Contains only the bare RSA public key fields exported by `jose.exportJWK()`
/// (`kty`, `n`, `e`, `kid`, `use`, and optionally `alg`) — without the X.509
/// certificate fields (`x5c`, `x5t`) present in [Jwk].
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class RsaJwk {
  /// {@macro rsa_jwk}
  const RsaJwk({
    required this.kty,
    required this.use,
    required this.kid,
    required this.n,
    required this.e,
    this.alg,
  });

  /// Decodes a JSON object into an [RsaJwk].
  factory RsaJwk.fromJson(Map<String, dynamic> json) => _$RsaJwkFromJson(json);

  /// Key type (must be `"RSA"`).
  final String kty;

  /// Key use (e.g., `"sig"`).
  final String use;

  /// Key ID.
  final String kid;

  /// RSA modulus (base64url-encoded, unpadded).
  final String n;

  /// RSA public exponent (base64url-encoded, unpadded).
  final String e;

  /// Algorithm — optional per RFC 7517 §4.4.
  final String? alg;
}

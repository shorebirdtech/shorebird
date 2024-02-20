import 'package:json_annotation/json_annotation.dart';

part 'jwk.g.dart';

/// {@template jwk}
/// A JSON Web Key (JWK) (https://datatracker.ietf.org/doc/html/rfc7517)
/// {@endtemplate}
@JsonSerializable()
class Jwk {
  /// {@macro jwk}
  const Jwk({
    required this.kty,
    required this.use,
    required this.kid,
    required this.x5c,
    required this.x5t,
    required this.n,
    required this.e,
  });

  /// Decodes a JSON object into a JWK.
  factory Jwk.fromJson(Map<String, dynamic> json) => _$JwkFromJson(json);

  /// Key type
  final String kty;

  /// Key use
  final String use;

  /// Key ID
  final String kid;

  /// X.509 certificate thumbprint
  final String x5t;

  /// X.509 certificate chain
  final List<String> x5c;

  /// RSA modulus
  final String n;

  /// RSA public exponent
  final String e;
}

import 'package:json_annotation/json_annotation.dart';

part 'jwt_header.g.dart';

/// {@template jwt_header}
/// A JWT header which contains the algorithm and token type.
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class JwtHeader {
  /// {@macro jwt_header}
  const JwtHeader({
    required this.alg,
    required this.kid,
    required this.typ,
  });

  /// Decode a [JwtHeader] from a `Map<String, dynamic>`.
  factory JwtHeader.fromJson(Map<String, dynamic> json) {
    return _$JwtHeaderFromJson(json);
  }

  /// Signature or encryption algorithm.
  final String alg;

  /// Key ID.
  final String kid;

  /// Type of token.
  final String typ;
}

import 'package:json_annotation/json_annotation.dart';

part 'jwt_payload.g.dart';

/// {@template jwt_payload}
/// A JWT payload which contains data.
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class JwtPayload {
  /// {@macro jwt_payload}
  JwtPayload({
    required this.exp,
    required this.iat,
    required this.aud,
    required this.iss,
    required this.sub,
    this.authTime,
  });

  /// Decode a [JwtPayload] from a `Map<String, dynamic>`.
  factory JwtPayload.fromJson(Map<String, dynamic> json) {
    return _$JwtPayloadFromJson(json);
  }

  /// Expiration time (seconds since Unix epoch).
  final int exp;

  /// Issued at (seconds since Unix epoch).
  final int iat;

  /// Audience (who or what the token is intended for).
  final String aud;

  /// Issuer (who created and signed this token).
  final String iss;

  /// Subject (whom the token refers to).
  final String sub;

  /// Time when authentication occurred.
  final int? authTime;
}

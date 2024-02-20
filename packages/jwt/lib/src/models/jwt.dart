import 'package:jwt/jwt.dart';
import 'package:jwt/src/encoding.dart';

/// {@template jwt}
/// A JWT (json web token)
/// {@endtemplate}
class Jwt {
  /// {@macro jwt}
  const Jwt({
    required this.header,
    required this.payload,
    required this.signature,
    this.claims = const <String, dynamic>{},
  });

  /// Decodes a JWT string of the format `header.payload.signature`. This does
  /// _not_ perform any verification that the JWT is valid.
  factory Jwt.parse(String string) {
    final parts = string.split('.');
    if (parts.length != 3) {
      throw const FormatException('Invalid JWT format');
    }

    final JwtHeader header;
    try {
      header = JwtHeader.fromJson(decodedJwtPart(parts[0]));
    } catch (_) {
      throw const FormatException('JWT header is malformed.');
    }

    final JwtPayload payload;
    try {
      payload = JwtPayload.fromJson(decodedJwtPart(parts[1]));
    } catch (_) {
      throw const FormatException('JWT payload is malformed.');
    }

    final signature = parts[2];

    return Jwt(
      header: header,
      payload: payload,
      signature: signature,
      claims: decodedJwtPart(parts[1]),
    );
  }

  /// {@macro jwt_header}
  final JwtHeader header;

  /// {@macro jwt_payload}
  final JwtPayload payload;

  /// JWT signature.
  final String signature;

  /// Token claims.
  final Map<String, dynamic> claims;
}

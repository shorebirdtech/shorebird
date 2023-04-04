import 'package:jwt/jwt.dart';

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

  /// {@macro jwt_header}
  final JwtHeader header;

  /// {@macro jwt_payload}
  final JwtPayload payload;

  /// JWT signature.
  final String signature;

  /// Token claims.
  final Map<String, dynamic> claims;
}

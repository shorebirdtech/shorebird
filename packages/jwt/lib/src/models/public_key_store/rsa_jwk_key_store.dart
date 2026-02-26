import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:jwt/src/models/public_key_store/public_key_store.dart';
import 'package:jwt/src/models/rsa_jwk.dart';
import 'package:pointycastle/pointycastle.dart' as pointycastle;

part 'rsa_jwk_key_store.g.dart';

/// {@template rsa_jwk_key_store}
/// A collection of bare RSA JSON Web Keys, as produced by Shorebird's auth
/// service.
///
/// Unlike [JwkKeyStore], which wraps X.509 certificates, this key store
/// converts base64url-encoded JWK parameters (`n`, `e`) directly into a
/// PointyCastle [pointycastle.RSAPublicKey].
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class RsaJwkKeyStore extends PublicKeyStore {
  /// {@macro rsa_jwk_key_store}
  RsaJwkKeyStore({required this.keys});

  /// The collection of RSA JWKs.
  final List<RsaJwk> keys;

  /// Decodes a JSON object into an [RsaJwkKeyStore].
  static RsaJwkKeyStore fromJson(Map<String, dynamic> json) =>
      _$RsaJwkKeyStoreFromJson(json);

  @override
  Iterable<String> get keyIds => keys.map((key) => key.kid);

  @override
  KeyMaterial? getKeyMaterial(String kid) {
    final key = keys.firstWhereOrNull((key) => key.kid == kid);
    if (key == null) return null;

    // Validate key type.
    if (key.kty != 'RSA') return null;

    // Only accept keys intended for signature verification.
    if (key.use != 'sig') return null;

    // Validate algorithm: accept RS256 or absent (verifier defaults to RS256).
    // Reject any other algorithm to prevent algorithm confusion attacks.
    if (key.alg != null && key.alg != 'RS256') return null;

    final modulus = _decodeBigInt(key.n);
    final exponent = _decodeBigInt(key.e);

    return RsaKeyMaterial(pointycastle.RSAPublicKey(modulus, exponent));
  }
}

/// Decodes a base64url-encoded unsigned big-endian integer (as used in JWK
/// `n` and `e` fields) into a [BigInt].
BigInt _decodeBigInt(String base64UrlValue) {
  final padded = base64UrlValue.padRight(
    base64UrlValue.length + (4 - base64UrlValue.length % 4) % 4,
    '=',
  );
  final bytes = base64Url.decode(padded);

  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

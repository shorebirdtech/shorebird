import 'package:jwt/src/jwks_format.dart';
import 'package:jwt/src/models/public_key_store/jwk_key_store.dart';
import 'package:jwt/src/models/public_key_store/key_value_key_store.dart';
import 'package:jwt/src/models/public_key_store/rsa_jwk_key_store.dart';
import 'package:pointycastle/pointycastle.dart' as pointycastle;

/// {@template key_material}
/// The material needed to verify a JWT signature.
/// {@endtemplate}
sealed class KeyMaterial {}

/// {@template pem_key_material}
/// Key material represented as a PEM-encoded string.
/// {@endtemplate}
class PemKeyMaterial extends KeyMaterial {
  /// {@macro pem_key_material}
  PemKeyMaterial(this.pem);

  /// The PEM-encoded key string.
  final String pem;
}

/// {@template rsa_key_material}
/// Key material represented as a raw RSA public key.
/// {@endtemplate}
class RsaKeyMaterial extends KeyMaterial {
  /// {@macro rsa_key_material}
  RsaKeyMaterial(this.publicKey);

  /// The RSA public key.
  final pointycastle.RSAPublicKey publicKey;
}

/// {@template public_key_store}
/// A store for the public keys.
/// {@endtemplate}
abstract class PublicKeyStore {
  /// {@macro public_key_store}
  const PublicKeyStore();

  /// Attempts to deserialize a [PublicKeyStore] from a JSON object for the
  /// given [format].
  static PublicKeyStore? tryDeserialize(
    Map<String, dynamic> json, {
    required JwksFormat format,
  }) {
    try {
      return switch (format) {
        JwksFormat.keyValue => KeyValueKeyStore.fromJson(json),
        JwksFormat.jwkCertificate => JwkKeyStore.fromJson(json),
        JwksFormat.rsaJwk => RsaJwkKeyStore.fromJson(json),
      };
    } on Exception {
      // Swallow deserialization exceptions and return null.
      return null;
    }
  }

  /// The key IDs contained in this store.
  Iterable<String> get keyIds;

  /// Returns the key material for the given key ID, if one exists.
  KeyMaterial? getKeyMaterial(String kid);
}

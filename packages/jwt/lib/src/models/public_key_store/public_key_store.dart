import 'package:jwt/src/models/public_key_store/jwk_key_store.dart';
import 'package:jwt/src/models/public_key_store/key_value_key_store.dart';

/// {@template public_key_store}
/// A store for the public keys.
/// {@endtemplate}
abstract class PublicKeyStore {
  /// {@macro public_key_store}
  const PublicKeyStore();

  /// Attempts to deserialize a [PublicKeyStore] from a JSON object. This will
  /// return the appropriate subclass of [PublicKeyStore] if the JSON object
  /// contains the necessary fields.
  static PublicKeyStore? tryDeserialize(Map<String, dynamic> json) {
    if (json.containsKey('keys')) {
      try {
        return JwkKeyStore.fromJson(json);
      } catch (_) {}
    } else {
      try {
        return KeyValueKeyStore.fromJson(json);
      } catch (_) {}
    }

    return null;
  }

  /// The key IDs contained in this store.
  Iterable<String> get keyIds;

  /// Returns a public key for the given key ID, if one exists.
  String? getPublicKey(String kid);
}

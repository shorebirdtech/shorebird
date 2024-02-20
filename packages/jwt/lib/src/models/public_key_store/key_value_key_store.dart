import 'package:jwt/src/models/public_key_store/public_key_store.dart';

/// {@template key_value_key_store}
/// A store for public keys of the form `id: value`. Google uses this format.
///
/// Ex: https://www.googleapis.com/oauth2/v1/certs
/// {@endtemplate}
class KeyValueKeyStore extends PublicKeyStore {
  /// {@macro key_value_key_store}
  const KeyValueKeyStore({required this.keys});

  /// Decodes a JSON object into a [KeyValueKeyStore].
  factory KeyValueKeyStore.fromJson(Map<String, dynamic> json) =>
      KeyValueKeyStore(keys: json.cast<String, String>());

  /// Map of all public key id/value pairs.
  final Map<String, String> keys;

  @override
  Iterable<String> get keyIds => keys.keys;

  @override
  String? getPublicKey(String kid) => keys[kid];
}

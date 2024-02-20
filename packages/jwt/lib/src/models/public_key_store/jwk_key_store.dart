import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:jwt/src/models/jwk.dart';
import 'package:jwt/src/models/public_key_store/public_key_store.dart';

part 'jwk_key_store.g.dart';

/// {@template jwk_key_store}
/// A collection of JSON Web Keys (JWKs). Microsoft uses this format.
///
/// Ex: https://login.microsoftonline.com/common/discovery/v2.0/keys
/// {@endtemplate}
@JsonSerializable()
class JwkKeyStore extends PublicKeyStore {
  /// {@macro jwk_key_store}
  JwkKeyStore({required this.keys});

  /// The collection of JWKs.
  final List<Jwk> keys;

  /// Decodes a JSON object into a [JwkKeyStore].
  static JwkKeyStore fromJson(Map<String, dynamic> json) =>
      _$JwkKeyStoreFromJson(json);

  @override
  Iterable<String> get keyIds => keys.map((key) => key.kid);

  @override
  String? getPublicKey(String kid) {
    final key = keys.firstWhereOrNull((key) => key.kid == kid)?.x5c.firstOrNull;
    if (key == null) {
      return null;
    }

    return '''
-----BEGIN CERTIFICATE-----
$key
-----END CERTIFICATE-----''';
  }
}

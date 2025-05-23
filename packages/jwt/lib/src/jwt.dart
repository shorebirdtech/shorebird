import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:jwt/jwt.dart';
import 'package:jwt/src/models/public_key_store/public_key_store.dart';
import 'package:meta/meta.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:rsa_pkcs/rsa_pkcs.dart' as rsa;
import 'package:ttl_cache/ttl_cache.dart';

/// A mapping of URLs to the public keys they contain.
/// Example URL: https://login.microsoftonline.com/common/discovery/v2.0/keys
@visibleForTesting
final publicKeyStores = TtlCache<String, PublicKeyStore>();

Future<PublicKeyStore?> _getPublicKeys(String url) async {
  final store = publicKeyStores.get(url);
  if (store != null) {
    return store;
  }

  final get = getOverride ?? http.get;
  final response = await get(Uri.parse(url));

  if (response.statusCode != HttpStatus.ok) {
    throw const JwtVerificationFailure('Could not fetch public keys.');
  }
  final maxAgeRegExp = RegExp(r'max-age=(\d+)');
  final match = maxAgeRegExp.firstMatch(response.headers['cache-control']!);
  final maxAge = int.parse(match!.group(1)!);

  final publicKeyStore = PublicKeyStore.tryDeserialize(
    json.decode(response.body) as Map<String, dynamic>,
  );

  if (publicKeyStore == null) {
    return null;
  }

  publicKeyStores.set(url, publicKeyStore, ttl: Duration(seconds: maxAge));

  return publicKeyStore;
}

/// {@template jwt_verification_failure}
/// An exception thrown during JWT verification.
/// {@endtemplate}
class JwtVerificationFailure implements Exception {
  /// {@macro jwt_verification_failure}
  const JwtVerificationFailure(this.reason);

  /// The reason for the verification failure.
  final String reason;

  @override
  String toString() => 'JwtVerificationFailure: $reason';
}

/// {@template jwt_extraction_failure}
/// An exception thrown during JWT extraction.
/// {@endtemplate}
class JwtExtractionFailure implements Exception {
  /// {@macro jwt_extraction_failure}
  const JwtExtractionFailure(this.reason);

  /// The reason for the extraction failure.
  final String reason;

  @override
  String toString() => 'JwtExtractionFailure: $reason';
}

/// Extracts a JWT from the Authorization header of the request. Throws a
/// [JwtExtractionFailure] if the header is missing or the token is malformed.
/// Does NOT verify the JWT.
Jwt extractFromRequestHeaders(Map<String, String> headers) {
  final caseInsensitveHeaders = headers.map(
    (key, value) => MapEntry(key.toLowerCase(), value),
  );
  final authorization = caseInsensitveHeaders[HttpHeaders.authorizationHeader];
  if (authorization == null) {
    throw const JwtExtractionFailure('Missing authorization header');
  }

  final tokenRegExp = RegExp('^Bearer (.*)');
  final token = tokenRegExp.firstMatch(authorization)?.group(1);
  if (token == null) {
    throw const JwtExtractionFailure('Malformed authorization header');
  }

  final Jwt jwt;
  try {
    jwt = Jwt.parse(token);
  } on Exception {
    throw const JwtExtractionFailure('Malformed JWT');
  }

  return jwt;
}

/// Verify the encoded [encodedJwt].
Future<Jwt> verify(
  String encodedJwt, {
  required String issuer,
  required Set<String> audience,
  required String publicKeysUrl,
}) async {
  final Jwt jwt;
  try {
    jwt = Jwt.parse(encodedJwt);
  } on FormatException catch (e) {
    throw JwtVerificationFailure(e.message);
  }

  final publicKeys = await _getPublicKeys(publicKeysUrl);
  if (publicKeys == null) {
    throw JwtVerificationFailure(
      'Invalid public keys returned by $publicKeysUrl.',
    );
  }

  await _verifyHeader(jwt.header, publicKeys.keyIds);
  _verifyPayload(jwt.payload, issuer, audience);

  // By using this keystore's key IDs to validate the header above, we've
  // guaranteed that there is a public key for this key ID.
  final publicKey = publicKeys.getPublicKey(jwt.header.kid)!;
  final bool isValid;
  try {
    isValid = _verifySignature(encodedJwt, publicKey);
  } on Exception {
    throw const JwtVerificationFailure('JWT signature is malformed.');
  }

  if (!isValid) {
    throw const JwtVerificationFailure('Invalid signature.');
  }

  // If we've made it this far, the JWT is now verified.
  return jwt;
}

Future<void> _verifyHeader(JwtHeader header, Iterable<String> keyIds) async {
  if (header.typ != 'JWT') {
    throw const JwtVerificationFailure('Invalid token type.');
  }

  if (header.alg != 'RS256') {
    throw const JwtVerificationFailure('Invalid algorithm.');
  }

  if (!keyIds.contains(header.kid)) {
    throw const JwtVerificationFailure('Invalid key id.');
  }
}

void _verifyPayload(JwtPayload payload, String issuer, Set<String> audience) {
  final now = clock.now();

  final exp = DateTime.fromMillisecondsSinceEpoch(payload.exp * 1000);
  if (exp.isBefore(now)) {
    throw const JwtVerificationFailure('Token has expired.');
  }

  final iat = DateTime.fromMillisecondsSinceEpoch(payload.iat * 1000);
  if (iat.isAfter(now)) {
    throw const JwtVerificationFailure('Token issued at a future time.');
  }

  if (payload.authTime != null) {
    final authTime = DateTime.fromMillisecondsSinceEpoch(
      payload.authTime! * 1000,
    );
    if (authTime.isAfter(now)) {
      throw const JwtVerificationFailure('Authenticated at a future time.');
    }
  }

  if (!audience.contains(payload.aud)) {
    throw const JwtVerificationFailure('Invalid audience.');
  }

  if (payload.iss != issuer) {
    throw const JwtVerificationFailure('Invalid issuer.');
  }

  if (payload.sub.isEmpty) {
    throw const JwtVerificationFailure('Invalid subject.');
  }
}

bool _verifySignature(String jwt, String publicKey) {
  final parts = jwt.split('.');
  final encodedHeader = parts[0];
  final encodedPayload = parts[1];
  final signature = parts[2];
  final body = utf8.encode('$encodedHeader.$encodedPayload');
  final sign = base64Url.decode(base64Padded(signature));

  final parser = rsa.RSAPKCSParser();
  final pair = parser.parsePEM(publicKey);
  if (pair.public is! rsa.RSAPublicKey) return false;
  final public = pair.public;

  final signer = Signer('SHA-256/RSA');
  final key = RSAPublicKey(public!.modulus, BigInt.from(public.publicExponent));
  final param = ParametersWithRandom(
    PublicKeyParameter<RSAPublicKey>(key),
    SecureRandom('AES/CTR/PRNG'),
  );
  signer.init(false, param);
  final rsaSignature = RSASignature(Uint8List.fromList(sign));
  return signer.verifySignature(Uint8List.fromList(body), rsaSignature);
}

/// Visible for testing only
@visibleForTesting
String base64Padded(String value) {
  final mod = value.length % 4;
  if (mod == 0) {
    return value;
  } else if (mod == 3) {
    return value.padRight(value.length + 1, '=');
  } else if (mod == 2) {
    return value.padRight(value.length + 2, '=');
  } else {
    return value; // let it fail when decoding
  }
}

/// Override for http.get.
/// Used for testing purposes only.
@visibleForTesting
Future<http.Response> Function(Uri uri)? getOverride;

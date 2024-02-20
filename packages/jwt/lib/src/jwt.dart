import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:jwt/jwt.dart';
import 'package:meta/meta.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:rsa_pkcs/rsa_pkcs.dart' as rsa;

/// {@template public_key_store}
/// A store for the public keys.
/// {@endtemplate}
class PublicKeyStore {
  /// {@macro public_key_store}
  const PublicKeyStore({required this.keys, required this.expiration});

  /// Map of all public key id/value pairs.
  final Map<String, String> keys;

  /// Expiration time.
  final DateTime expiration;
}

PublicKeyStore? _publicKeyStore;

Future<Map<String, String>> _getPublicKeys(String url) async {
  if (_publicKeyStore?.expiration.isAfter(clock.now()) ?? false) {
    return _publicKeyStore!.keys;
  }

  final get = getOverride ?? http.get;
  final response = await get(Uri.parse(url));

  if (response.statusCode != HttpStatus.ok) {
    throw const JwtVerificationFailure('Could not fetch public keys.');
  }
  final maxAgeRegExp = RegExp(r'max-age=(\d+)');
  final match = maxAgeRegExp.firstMatch(response.headers['cache-control']!);
  final maxAge = int.parse(match!.group(1)!);
  final publicKeys = (json.decode(response.body) as Map<String, dynamic>)
      .cast<String, String>();

  _publicKeyStore = PublicKeyStore(
    keys: publicKeys,
    expiration: clock.now().add(Duration(seconds: maxAge)),
  );

  return publicKeys;
}

/// Typedef for a function that returns the public keys asynchronously.
typedef GetPublicKeys = Future<Map<String, String>> Function();

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

/// Verify the provided [jwt].
Future<Jwt> verify(
  String jwt, {
  required String issuer,
  required Set<String> audience,
  required String publicKeysUrl,
}) async {
  final Jwt unverified;
  try {
    unverified = Jwt.unverifiedFromString(jwt);
  } on FormatException catch (e) {
    throw JwtVerificationFailure(e.message);
  }

  final publicKeys = await _getPublicKeys(publicKeysUrl);

  await _verifyHeader(unverified.header, publicKeys);
  _verifyPayload(unverified.payload, issuer, audience);

  final isValid = _verifySignature(jwt, publicKeys[unverified.header.kid]!);
  if (!isValid) {
    throw const JwtVerificationFailure('Invalid signature.');
  }

  // If we've made it this far, the JWT is now verified.
  return unverified;
}

Future<void> _verifyHeader(
  JwtHeader header,
  Map<String, dynamic> publicKeys,
) async {
  if (header.typ != 'JWT') {
    throw const JwtVerificationFailure('Invalid token type.');
  }

  if (header.alg != 'RS256') {
    throw const JwtVerificationFailure('Invalid algorithm.');
  }

  if (!publicKeys.containsKey(header.kid)) {
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

  try {
    final signer = Signer('SHA-256/RSA');
    final key = RSAPublicKey(
      public!.modulus,
      BigInt.from(public.publicExponent),
    );
    final param = ParametersWithRandom(
      PublicKeyParameter<RSAPublicKey>(key),
      SecureRandom('AES/CTR/PRNG'),
    );
    signer.init(false, param);
    final rsaSignature = RSASignature(Uint8List.fromList(sign));
    return signer.verifySignature(Uint8List.fromList(body), rsaSignature);
  } catch (_) {
    return false;
  }
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

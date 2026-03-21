import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:http/http.dart';
import 'package:jwt/jwt.dart';
import 'package:jwt/src/models/public_key_store/public_key_store.dart';
import 'package:jwt/src/models/public_key_store/rsa_jwk_key_store.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/pointycastle.dart' as pc;
import 'package:test/test.dart';

/// Encodes a [BigInt] as an unpadded base64url string (JWK `n`/`e` format).
String _encodeBigInt(BigInt value) {
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return base64Url.encode(Uint8List.fromList(bytes)).replaceAll('=', '');
}

pc.SecureRandom _secureRandom() {
  final sr = pc.SecureRandom('AES/CTR/PRNG');
  final random = Random.secure();
  final seeds = List<int>.generate(32, (_) => random.nextInt(256));
  sr.seed(pc.KeyParameter(Uint8List.fromList(seeds)));
  return sr;
}

pc.AsymmetricKeyPair<pc.RSAPublicKey, pc.RSAPrivateKey> _generateRsaKeyPair() {
  final keyGen = pc.KeyGenerator('RSA');
  keyGen.init(
    pc.ParametersWithRandom(
      pc.RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
      _secureRandom(),
    ),
  );
  final pair = keyGen.generateKeyPair();
  return pc.AsymmetricKeyPair(
    pair.publicKey as pc.RSAPublicKey,
    pair.privateKey as pc.RSAPrivateKey,
  );
}

/// Creates a signed JWT from the given [header], [payload], and [privateKey].
String _createSignedJwt({
  required Map<String, dynamic> header,
  required Map<String, dynamic> payload,
  required pc.RSAPrivateKey privateKey,
}) {
  final encodedHeader = base64Url
      .encode(utf8.encode(json.encode(header)))
      .replaceAll('=', '');
  final encodedPayload = base64Url
      .encode(utf8.encode(json.encode(payload)))
      .replaceAll('=', '');
  final signingInput = '$encodedHeader.$encodedPayload';

  final signer = pc.Signer('SHA-256/RSA');
  signer.init(
    true,
    pc.ParametersWithRandom(
      pc.PrivateKeyParameter<pc.RSAPrivateKey>(privateKey),
      _secureRandom(),
    ),
  );
  final signature =
      signer.generateSignature(
            Uint8List.fromList(utf8.encode(signingInput)),
          )
          as pc.RSASignature;
  final encodedSignature = base64Url
      .encode(signature.bytes)
      .replaceAll('=', '');

  return '$signingInput.$encodedSignature';
}

void main() {
  const token = // cspell: disable-next-line
      '''eyJhbGciOiJSUzI1NiIsImtpZCI6ImMxMGM5MGJhNGMzNjYzNTE2ZTA3MDdkMGU5YTg5NDgxMDYyODUxNTgiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL3NlY3VyZXRva2VuLmdvb2dsZS5jb20vbXktYXBwIiwiYXVkIjoibXktYXBwIiwiYXV0aF90aW1lIjoxNjQzNjg0MjY2LCJ1c2VyX2lkIjoiRzR1MzdXdk90dmVWR0pRb1pCWGpxcHVWazZWMiIsInN1YiI6Ikc0dTM3V3ZPdHZlVkdKUW9aQlhqcXB1Vms2VjIiLCJpYXQiOjE2NDM2ODQyNjYsImV4cCI6MTY0MzY4Nzg2NiwiZW1haWwiOiJ0ZXN0QGdtYWlsLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJmaXJlYmFzZSI6eyJpZGVudGl0aWVzIjp7ImVtYWlsIjpbInRlc3RAZ21haWwuY29tIl19LCJzaWduX2luX3Byb3ZpZGVyIjoicGFzc3dvcmQifX0.bUWnX_XmR1d9EmeFeYSsK_CHU1u9NPIHgyaQueZ6urYOtxvuL_QodjPl0c9CBJwctwPnxVyRmkeNCw0oF9xBgph0NApLL4FIG6vpDPZfW9txZBYr8xIvaqvmD0diACENAQdjRT2XmyEdQ2-U7SsTonybHmLoU9FMQTjAgw4NCALQvExfB6rtQ9GDsOBt1xoBkB3Vo7a5OmugZ1aHXF69b8As6137-Dggf5qx5R3oLRFovICMMesQziE3vGi-WKcbQxSeiD-9a6ShPAhk41XiyjFGDEOtUCQo63uwQnMw3g0KVtC6bzIyFq-E91vhxumxXzxPYC-kg7iUYiSZy7Y-Aw''';
  const tokenInvalidPayload = // cspell: disable-next-line
      '''eyJhbGciOiJSUzI1NiIsImtpZCI6ImMxMGM5MGJhNGMzNjYzNTE2ZTA3MDdkMGU5YTg5NDgxMDYyODUxNTgiLCJ0eXAiOiJKV1QifQ.invalid.bUWnX_XmR1d9EmeFeYSsK_CHU1u9NPIHgyaQueZ6urYOtxvuL_QodjPl0c9CBJwctwPnxVyRmkeNCw0oF9xBgph0NApLL4FIG6vpDPZfW9txZBYr8xIvaqvmD0diACENAQdjRT2XmyEdQ2-U7SsTonybHmLoU9FMQTjAgw4NCALQvExfB6rtQ9GDsOBt1xoBkB3Vo7a5OmugZ1aHXF69b8As6137-Dggf5qx5R3oLRFovICMMesQziE3vGi-WKcbQxSeiD-9a6ShPAhk41XiyjFGDEOtUCQo63uwQnMw3g0KVtC6bzIyFq-E91vhxumxXzxPYC-kg7iUYiSZy7Y-Aw''';
  const tokenNoAuthTime = // cspell: disable-next-line
      '''eyJhbGciOiJSUzI1NiIsImtpZCI6ImMxMGM5MGJhNGMzNjYzNTE2ZTA3MDdkMGU5YTg5NDgxMDYyODUxNTgiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL3NlY3VyZXRva2VuLmdvb2dsZS5jb20vbXktYXBwIiwiYXVkIjoibXktYXBwIiwidXNlcl9pZCI6Ikc0dTM3V3ZPdHZlVkdKUW9aQlhqcXB1Vms2VjIiLCJzdWIiOiJHNHUzN1d2T3R2ZVZHSlFvWkJYanFwdVZrNlYyIiwiaWF0IjoxNjQzNjg0MjY2LCJleHAiOjE2NDM2ODc4NjYsImVtYWlsIjoidGVzdEBnbWFpbC5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwiZmlyZWJhc2UiOnsiaWRlbnRpdGllcyI6eyJlbWFpbCI6WyJ0ZXN0QGdtYWlsLmNvbSJdfSwic2lnbl9pbl9wcm92aWRlciI6InBhc3N3b3JkIn19.ZWCadE43mUk43cPQdNCCi4WhDgB4ZsDT9rhPGQq_1uFPhzkVrCSRcjUhwkzH11VLap_MVurNvI_pGWbu9Z4CRPvGFzXPpuNveWy2qFPEa4jcM-R40vsbrP30vNnrp4PrmqgLar0vWs6FZ2g9fbjU8L1LaU5ik31OKSXufTIKn_hPHhyIC33tYTpWzG3Abq3H9EELHUXKW9nEcN8YYnOHAZ3A6ymb3DyBguhf2O-XAIlrn1WoxRRqlukFGSmprk7heonbVUTzoc3sIDZcC-Cj1U9wTee1NmqmU7v3SvpBRGnuXz-5rzSRHblyVxn_EEfCYwjsDUwetYpyFcCs5dqPlQ''';
  const tokenWithNoMatchingKid = // cspell: disable-next-line
      '''eyJhbGciOiJSUzI1NiIsImtpZCI6IjEyMzQiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL3NlY3VyZXRva2VuLmdvb2dsZS5jb20vbXktYXBwIiwiYXVkIjoibXktYXBwIiwidXNlcl9pZCI6Ikc0dTM3V3ZPdHZlVkdKUW9aQlhqcXB1Vms2VjIiLCJzdWIiOiJHNHUzN1d2T3R2ZVZHSlFvWkJYanFwdVZrNlYyIiwiaWF0IjoxNjQzNjg0MjY2LCJleHAiOjE2NDM2ODc4NjYsImVtYWlsIjoidGVzdEBnbWFpbC5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwiZmlyZWJhc2UiOnsiaWRlbnRpdGllcyI6eyJlbWFpbCI6WyJ0ZXN0QGdtYWlsLmNvbSJdfSwic2lnbl9pbl9wcm92aWRlciI6InBhc3N3b3JkIn19.RBAwg-Ttf36aDkVR97Rd50aMp-0yzk8do_4AUPFi9nEhKu0Ye8ox_9hdTBttJYxoOq0NbH2zz0JHSnSHqoTvCleVhoGqg8YghzH0NiqncPfDzi-IcRfy2K8CrOoXuqXaj3YWrbrzNWAYV46eFmvI2TmPO55AyFOjhvLpW-uf96ceOPjueZm8o5K2DZym86BAhSdShknONV2O7b2vW34TXf3UJdISs5p9z6Si4JOWGjbVPY45CO16ODdDxyUGUM2-IVQloB7bg0nMqQbIjKDoO5g9d1nguR2Z-YBiv0BX1MDWDlrBsMAzzRVaFlf6YQS1LKxu2tnMdCrBnK_Wvqt5sQ''';
  const tokenInvalidSignature = // cspell: disable-next-line
      '''eyJhbGciOiJSUzI1NiIsImtpZCI6ImMxMGM5MGJhNGMzNjYzNTE2ZTA3MDdkMGU5YTg5NDgxMDYyODUxNTgiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL3NlY3VyZXRva2VuLmdvb2dsZS5jb20vbXktYXBwIiwiYXVkIjoibXktYXBwIiwiYXV0aF90aW1lIjoxNjQzNjg0MjY2LCJ1c2VyX2lkIjoiRzR1MzdXdk90dmVWR0pRb1pCWGpxcHVWazZWMiIsInN1YiI6Ikc0dTM3V3ZPdHZlVkdKUW9aQlhqcXB1Vms2VjIiLCJpYXQiOjE2NDM2ODQyNjYsImV4cCI6MTY0MzY4Nzg2NiwiZW1haWwiOiJ0ZXN0QGdtYWlsLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJmaXJlYmFzZSI6eyJpZGVudGl0aWVzIjp7ImVtYWlsIjpbInRlc3RAZ21haWwuY29tIl19LCJzaWduX2luX3Byb3ZpZGVyIjoicGFzc3dvcmQifX0.invalid-signature''';
  const keyValuePublicKeysUrl =
      'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';
  const jwkPublicKeysUrl =
      'https://login.microsoftonline.com/common/discovery/v2.0/keys';
  final jwkKeyStoreJsonString = File(
    p.join('test', 'fixtures', 'jwk_key_store.json'),
  ).readAsStringSync();
  final keyValueKeyStoreString = File(
    p.join('test', 'fixtures', 'key_value_key_store.json'),
  ).readAsStringSync();
  final expiresAt = DateTime.fromMillisecondsSinceEpoch(1643687866 * 1000);
  final validTime = expiresAt.subtract(const Duration(minutes: 15));

  // Test values for RsaJwkKeyStore unit tests.
  final testModulus = BigInt.parse('12345678901234567890');
  final testExponent = BigInt.from(65537);
  final testModulusB64 = _encodeBigInt(testModulus);
  final testExponentB64 = _encodeBigInt(testExponent);

  late String keyStoreResponseBody;

  setUp(() {
    publicKeyStores.clear();
    getOverride = (Uri uri) async {
      return Response(
        keyStoreResponseBody,
        HttpStatus.ok,
        headers: {'cache-control': 'max-age=3600'},
      );
    };
  });

  group(JwtExtractionFailure, () {
    group('toString', () {
      test('returns the reason', () {
        const reason = 'reason';
        const failure = JwtExtractionFailure(reason);
        expect(failure.toString(), equals('JwtExtractionFailure: $reason'));
      });
    });
  });

  group('extractFromRequestHeaders', () {
    group('when no authorization header is provided', () {
      test('throws JwtExtractionFailure', () {
        expect(
          () => extractFromRequestHeaders({}),
          throwsA(
            isA<JwtExtractionFailure>().having(
              (e) => e.reason,
              'reason',
              'Missing authorization header',
            ),
          ),
        );
      });
    });

    group('when authorization header is malformed', () {
      test('throws JwtExtractionFailure', () {
        expect(
          () => extractFromRequestHeaders({
            HttpHeaders.authorizationHeader: 'not-a-jwt',
          }),
          throwsA(
            isA<JwtExtractionFailure>().having(
              (e) => e.reason,
              'reason',
              'Malformed authorization header',
            ),
          ),
        );
      });
    });

    group('when authorization header cannot be parsed into jwt', () {
      test('throws JwtExtractionFailure', () {
        expect(
          () => extractFromRequestHeaders({
            HttpHeaders.authorizationHeader: 'Bearer not-a-jwt',
          }),
          throwsA(
            isA<JwtExtractionFailure>().having(
              (e) => e.reason,
              'reason',
              'Malformed JWT',
            ),
          ),
        );
      });
    });

    group('when authorization header contains a valid jwt', () {
      test('returns a jwt', () {
        final jwt = extractFromRequestHeaders({
          HttpHeaders.authorizationHeader: 'Bearer $token',
        });
        expect(jwt.payload.aud, equals('my-app'));
        expect(
          jwt.payload.iss,
          equals('https://securetoken.google.com/my-app'),
        );
      });
    });
  });

  group('RsaJwkKeyStore', () {
    test('deserializes and returns expected key IDs', () {
      final store = RsaJwkKeyStore.fromJson({
        'keys': [
          {
            'kty': 'RSA',
            'use': 'sig',
            'kid': 'key-1',
            'n': testModulusB64,
            'e': testExponentB64,
          },
          {
            'kty': 'RSA',
            'use': 'sig',
            'kid': 'key-2',
            'n': testModulusB64,
            'e': testExponentB64,
          },
        ],
      });
      expect(store.keyIds, containsAll(['key-1', 'key-2']));
    });

    test('getKeyMaterial returns RsaKeyMaterial with correct values', () {
      final store = RsaJwkKeyStore.fromJson({
        'keys': [
          {
            'kty': 'RSA',
            'use': 'sig',
            'kid': 'key-1',
            'n': testModulusB64,
            'e': testExponentB64,
          },
        ],
      });
      final material = store.getKeyMaterial('key-1');
      expect(material, isA<RsaKeyMaterial>());
      final rsaMaterial = material! as RsaKeyMaterial;
      expect(rsaMaterial.publicKey.modulus, equals(testModulus));
      expect(rsaMaterial.publicKey.exponent, equals(testExponent));
    });

    test('unknown kid returns null', () {
      final store = RsaJwkKeyStore.fromJson({
        'keys': [
          {
            'kty': 'RSA',
            'use': 'sig',
            'kid': 'key-1',
            'n': testModulusB64,
            'e': testExponentB64,
          },
        ],
      });
      expect(store.getKeyMaterial('nonexistent'), isNull);
    });

    test('accepts key with alg RS256', () {
      final store = RsaJwkKeyStore.fromJson({
        'keys': [
          {
            'kty': 'RSA',
            'use': 'sig',
            'kid': 'key-1',
            'n': testModulusB64,
            'e': testExponentB64,
            'alg': 'RS256',
          },
        ],
      });
      expect(store.getKeyMaterial('key-1'), isA<RsaKeyMaterial>());
    });

    test('accepts key with absent alg', () {
      final store = RsaJwkKeyStore.fromJson({
        'keys': [
          {
            'kty': 'RSA',
            'use': 'sig',
            'kid': 'key-1',
            'n': testModulusB64,
            'e': testExponentB64,
          },
        ],
      });
      expect(store.getKeyMaterial('key-1'), isA<RsaKeyMaterial>());
    });

    test('rejects key with wrong alg', () {
      for (final wrongAlg in ['RS512', 'ES256', 'HS256']) {
        final store = RsaJwkKeyStore.fromJson({
          'keys': [
            {
              'kty': 'RSA',
              'use': 'sig',
              'kid': 'key-1',
              'n': testModulusB64,
              'e': testExponentB64,
              'alg': wrongAlg,
            },
          ],
        });
        expect(
          store.getKeyMaterial('key-1'),
          isNull,
          reason: 'alg=$wrongAlg should be rejected',
        );
      }
    });

    test('rejects key with wrong kty', () {
      final store = RsaJwkKeyStore.fromJson({
        'keys': [
          {
            'kty': 'EC',
            'use': 'sig',
            'kid': 'key-1',
            'n': testModulusB64,
            'e': testExponentB64,
          },
        ],
      });
      expect(store.getKeyMaterial('key-1'), isNull);
    });

    test('rejects key with wrong use', () {
      final store = RsaJwkKeyStore.fromJson({
        'keys': [
          {
            'kty': 'RSA',
            'use': 'enc',
            'kid': 'key-1',
            'n': testModulusB64,
            'e': testExponentB64,
          },
        ],
      });
      expect(store.getKeyMaterial('key-1'), isNull);
    });
  });

  group('verify', () {
    group('when key store is key-value', () {
      const issuer = 'https://securetoken.google.com/my-app';
      const audience = 'my-app';

      setUp(() {
        keyStoreResponseBody = keyValueKeyStoreString;
      });

      test('can verify an expired jwt', () async {
        await expectLater(
          () => verify(
            token,
            audience: {audience},
            issuer: issuer,
            publicKeysUrl: keyValuePublicKeysUrl,
            jwksFormat: JwksFormat.keyValue,
          ),
          throwsA(
            isA<JwtVerificationFailure>().having(
              (e) => e.reason,
              'reason',
              'Token has expired.',
            ),
          ),
        );
      });

      test(
        'throws a JwtVerificationFailure if string is not valid jwt',
        () async {
          await expectLater(
            () => verify(
              'not.a.jwt',
              audience: {audience},
              issuer: issuer,
              publicKeysUrl: keyValuePublicKeysUrl,
              jwksFormat: JwksFormat.keyValue,
            ),
            throwsA(
              isA<JwtVerificationFailure>().having(
                (e) => e.reason,
                'reason',
                'JWT header is malformed.',
              ),
            ),
          );
        },
      );

      test('throws a JwtVerificationFailure if payload is not valid', () async {
        await expectLater(
          () => verify(
            tokenInvalidPayload,
            audience: {audience},
            issuer: issuer,
            publicKeysUrl: keyValuePublicKeysUrl,
            jwksFormat: JwksFormat.keyValue,
          ),
          throwsA(
            isA<JwtVerificationFailure>().having(
              (e) => e.reason,
              'reason',
              'JWT payload is malformed.',
            ),
          ),
        );
      });

      test(
        'throws a JwtVerificationFailure if signature is not valid',
        () async {
          await withClock(Clock.fixed(validTime), () async {
            await expectLater(
              () => verify(
                tokenInvalidSignature,
                audience: {audience},
                issuer: issuer,
                publicKeysUrl: keyValuePublicKeysUrl,
                jwksFormat: JwksFormat.keyValue,
              ),
              throwsA(
                isA<JwtVerificationFailure>().having(
                  (e) => e.reason,
                  'reason',
                  'JWT signature is malformed.',
                ),
              ),
            );
          });
        },
      );

      test('throws exception if jwt has no matching public key id', () async {
        await withClock(Clock.fixed(validTime), () async {
          await expectLater(
            () => verify(
              tokenWithNoMatchingKid,
              audience: {audience},
              issuer: issuer,
              publicKeysUrl: keyValuePublicKeysUrl,
              jwksFormat: JwksFormat.keyValue,
            ),
            throwsA(
              isA<JwtVerificationFailure>().having(
                (e) => e.reason,
                'reason',
                'Invalid key id.',
              ),
            ),
          );
        });
      });

      test('throws exception if invalid keys are provided '
          'by the publicKeysUrl (KeyValueKeyStore)', () async {
        getOverride = (Uri uri) async {
          return Response(
            '{"123": 456}',
            HttpStatus.ok,
            headers: {'cache-control': 'max-age=3600'},
          );
        };

        await withClock(Clock.fixed(validTime), () async {
          await expectLater(
            () => verify(
              tokenWithNoMatchingKid,
              audience: {audience},
              issuer: issuer,
              publicKeysUrl: keyValuePublicKeysUrl,
              jwksFormat: JwksFormat.keyValue,
            ),
            throwsA(
              isA<JwtVerificationFailure>().having(
                (e) => e.reason,
                'reason',
                '''Invalid public keys returned by https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com.''',
              ),
            ),
          );
        });
      });

      test('throws exception if invalid keys are provided '
          'by the publicKeysUrl (JwkKeyStore)', () async {
        getOverride = (Uri uri) async {
          return Response(
            '{"keys": 456}',
            HttpStatus.ok,
            headers: {'cache-control': 'max-age=3600'},
          );
        };

        await withClock(Clock.fixed(validTime), () async {
          await expectLater(
            () => verify(
              tokenWithNoMatchingKid,
              audience: {audience},
              issuer: issuer,
              publicKeysUrl: keyValuePublicKeysUrl,
              jwksFormat: JwksFormat.jwkCertificate,
            ),
            throwsA(
              isA<JwtVerificationFailure>().having(
                (e) => e.reason,
                'reason',
                '''Invalid public keys returned by https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com.''',
              ),
            ),
          );
        });
      });

      test('throws exception if invalid keys are provided '
          'by the publicKeysUrl (RsaJwkKeyStore)', () async {
        getOverride = (Uri uri) async {
          return Response(
            '{"keys": 456}',
            HttpStatus.ok,
            headers: {'cache-control': 'max-age=3600'},
          );
        };

        await withClock(Clock.fixed(validTime), () async {
          await expectLater(
            () => verify(
              tokenWithNoMatchingKid,
              audience: {audience},
              issuer: issuer,
              publicKeysUrl: keyValuePublicKeysUrl,
              jwksFormat: JwksFormat.rsaJwk,
            ),
            throwsA(
              isA<JwtVerificationFailure>().having(
                (e) => e.reason,
                'reason',
                '''Invalid public keys returned by https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com.''',
              ),
            ),
          );
        });
      });

      test('can verify an invalid audience', () async {
        await withClock(Clock.fixed(validTime), () async {
          try {
            await verify(
              token,
              audience: {'invalid-audience'},
              issuer: issuer,
              publicKeysUrl: keyValuePublicKeysUrl,
              jwksFormat: JwksFormat.keyValue,
            );
            fail('should throw');
          } on Exception catch (error) {
            expect(
              error,
              isA<JwtVerificationFailure>().having(
                (e) => e.reason,
                'reason',
                'Invalid audience.',
              ),
            );
          }
        });
      });

      test('can verify an invalid issuer', () async {
        await withClock(Clock.fixed(validTime), () async {
          try {
            await verify(
              token,
              audience: {audience},
              issuer: 'https://invalid/issuer',
              publicKeysUrl: keyValuePublicKeysUrl,
              jwksFormat: JwksFormat.keyValue,
            );
            fail('should throw');
          } on Exception catch (error) {
            expect(
              error,
              isA<JwtVerificationFailure>().having(
                (e) => e.reason,
                'reason',
                'Invalid issuer.',
              ),
            );
          }
        });
      });

      test('can verify a valid jwt', () async {
        await withClock(Clock.fixed(validTime), () async {
          final jwt = await verify(
            token,
            audience: {audience},
            issuer: issuer,
            publicKeysUrl: keyValuePublicKeysUrl,
            jwksFormat: JwksFormat.keyValue,
          );
          expect(jwt, isA<Jwt>());
        });
      });

      test('can verify a valid jwt (multiple audiences)', () async {
        await withClock(Clock.fixed(validTime), () async {
          final jwt = await verify(
            token,
            audience: {'other-audience', audience},
            issuer: issuer,
            publicKeysUrl: keyValuePublicKeysUrl,
            jwksFormat: JwksFormat.keyValue,
          );
          expect(jwt, isA<Jwt>());
        });
      });

      test('can verify a valid jwt w/out auth_time', () async {
        await withClock(Clock.fixed(validTime), () async {
          final jwt = await verify(
            tokenNoAuthTime,
            audience: {audience},
            issuer: issuer,
            publicKeysUrl: keyValuePublicKeysUrl,
            jwksFormat: JwksFormat.keyValue,
          );
          expect(jwt, isA<Jwt>());
        });
      });

      group('when key store is JWK store', () {
        const token = // cspell: disable-next-line
            '''eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6InRSNHdrWWhIeEhvX3FlcHJTMDhDdXc4eGNPdyJ9.eyJ2ZXIiOiIyLjAiLCJpc3MiOiJodHRwczovL2xvZ2luLm1pY3Jvc29mdG9ubGluZS5jb20vOTE4ODA0MGQtNmM2Ny00YzViLWIxMTItMzZhMzA0YjY2ZGFkL3YyLjAiLCJzdWIiOiJBQUFBQUFBQUFBQUFBQUFBQUFBQUFKclpOMmI0eldUNzhQWFJEN2J6dkxrIiwiYXVkIjoiYzRhZjk1NjYtOGEzNi00MzQ4LWI0MTMtZGFiNjY1Yjg3MTdkIiwiZXhwIjoxNzA4NTQ2MDYwLCJpYXQiOjE3MDg0NTkzNjAsIm5iZiI6MTcwODQ1OTM2MCwiZW1haWwiOiJicnlhbm9sdG1hbkBob3RtYWlsLmNvbSIsInRpZCI6IjkxODgwNDBkLTZjNjctNGM1Yi1iMTEyLTM2YTMwNGI2NmRhZCIsImFpbyI6IkRtUE91OTNxdWlSNm9OYVBrMjl1dVFSTkhSN0NIS0V4VDlrSE5DamVJIUdpN3JMQks2SDZYYzdkUWl2ZmRxTVZ5VExuNDMxUWRaTXpPSHQqaDQ2NWViQTlBWE9RdzhOdlM3dzNTbFREWU9iOW52OGh2SHNDTXZqdlJJMzRaWXlPbiE2MHBUcXghWnVmeTF0VnRGMWp6VEVsQmlUTjRrOWJIU0RDUFZaU1BlaXNzYjFLdmhCamc4biFPUSptNWszSmZ3JCQifQ.PhZfpmMmhlW_w9P-EQjcA-DgD0Mxnufxgn6rsKlQYtRn2hmT8uGOlMpMthYIeYLhVPtQqPyHDdW-0GxJ3ROK6prlogvPt8SxY8lSiJ6a4XCNmGop-7MxWGkYhqnMw21TKiSsGIr5LSuD3b_5RK6uBipra0rf819Wlvp6JbXulGSHt9N_qyq8328npCHRYbIDOBcOgDjnPjDFp_pJ99-itCsM8OO0npZJZ64MmlENgEYswnOQYlCShF1HLQwes7uGuw8ZBik-XSu44iJKJ9u4Ai3BjpxYdMFmMZ-B4DpF3uWpFsK-X9tMbi23gwufu5X_6aqtZYRLg052M1SUaBiMUw''';
        // cspell: disable-next-line
        const audience = 'c4af9566-8a36-4348-b413-dab665b8717d';
        const issuer =
            '''https://login.microsoftonline.com/9188040d-6c67-4c5b-b112-36a304b66dad/v2.0''';

        setUp(() {
          keyStoreResponseBody = jwkKeyStoreJsonString;
        });

        test('can verify a valid jwt', () async {
          final time = DateTime(2024, 2, 21);
          await withClock(Clock.fixed(time), () async {
            final jwt = await verify(
              token,
              audience: {audience},
              issuer: issuer,
              publicKeysUrl: jwkPublicKeysUrl,
              jwksFormat: JwksFormat.jwkCertificate,
            );
            expect(jwt, isA<Jwt>());
          });
        });
      });
    });

    group('when key store is RSA JWK store', () {
      late pc.AsymmetricKeyPair<pc.RSAPublicKey, pc.RSAPrivateKey> rsaKeyPair;
      late String rsaJwkToken;
      late String rsaJwkKeyStoreJson;
      const rsaJwkPublicKeysUrl =
          'https://auth.example.com/.well-known/jwks.json';
      const rsaJwkKid = 'test-rsa-key-1';
      const rsaJwkIssuer = 'https://auth.example.com';
      const rsaJwkAudience = 'test-audience';

      setUpAll(() {
        rsaKeyPair = _generateRsaKeyPair();

        final publicKey = rsaKeyPair.publicKey;
        final nB64 = _encodeBigInt(publicKey.modulus!);
        final eB64 = _encodeBigInt(publicKey.exponent!);

        final now = DateTime(2024, 6, 1);
        final iat = now.millisecondsSinceEpoch ~/ 1000;
        final exp =
            now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;

        rsaJwkToken = _createSignedJwt(
          header: {'alg': 'RS256', 'kid': rsaJwkKid, 'typ': 'JWT'},
          payload: {
            'iss': rsaJwkIssuer,
            'aud': rsaJwkAudience,
            'sub': 'test-user-123',
            'iat': iat,
            'exp': exp,
          },
          privateKey: rsaKeyPair.privateKey,
        );

        rsaJwkKeyStoreJson = json.encode({
          'keys': [
            {
              'kty': 'RSA',
              'use': 'sig',
              'kid': rsaJwkKid,
              'n': nB64,
              'e': eB64,
            },
          ],
        });
      });

      setUp(() {
        keyStoreResponseBody = rsaJwkKeyStoreJson;
      });

      test('can verify a valid jwt', () async {
        final time = DateTime(2024, 6, 1, 0, 15);
        await withClock(Clock.fixed(time), () async {
          final jwt = await verify(
            rsaJwkToken,
            audience: {rsaJwkAudience},
            issuer: rsaJwkIssuer,
            publicKeysUrl: rsaJwkPublicKeysUrl,
            jwksFormat: JwksFormat.rsaJwk,
          );
          expect(jwt, isA<Jwt>());
          expect(jwt.payload.sub, equals('test-user-123'));
          expect(jwt.payload.iss, equals(rsaJwkIssuer));
          expect(jwt.payload.aud, equals(rsaJwkAudience));
        });
      });

      test('rejects a jwt signed with a different key', () async {
        // Provide a different public key in the JWKS so signature won't match.
        final wrongKeyPair = _generateRsaKeyPair();
        final wrongPublic = wrongKeyPair.publicKey;
        keyStoreResponseBody = json.encode({
          'keys': [
            {
              'kty': 'RSA',
              'use': 'sig',
              'kid': rsaJwkKid,
              'n': _encodeBigInt(wrongPublic.modulus!),
              'e': _encodeBigInt(wrongPublic.exponent!),
            },
          ],
        });
        publicKeyStores.clear();

        final time = DateTime(2024, 6, 1, 0, 15);
        await withClock(Clock.fixed(time), () async {
          await expectLater(
            () => verify(
              rsaJwkToken,
              audience: {rsaJwkAudience},
              issuer: rsaJwkIssuer,
              publicKeysUrl: rsaJwkPublicKeysUrl,
              jwksFormat: JwksFormat.rsaJwk,
            ),
            throwsA(
              isA<JwtVerificationFailure>().having(
                (e) => e.reason,
                'reason',
                'Invalid signature.',
              ),
            ),
          );
        });
      });
    });
  });

  group('base64Padded', () {
    test('does not add padding when mod 4 == 0', () {
      const value = 'aaaa';
      expect(base64Padded(value), equals(value));
    });

    test('does not add padding when mod 4 == 1', () {
      const value = 'aaaaa';
      expect(base64Padded(value), equals(value));
    });

    test('adds padding when mod 4 == 3', () {
      const value = 'aaaaaaa';
      expect(base64Padded(value), equals('$value='));
    });

    test('adds padding when mod 4 == 2', () {
      const value = 'aaaaaa';
      expect(base64Padded(value), equals('$value=='));
    });
  });

  group('JwtVerificationFailure', () {
    test('toString is correct', () {
      const reason = 'reason';
      const failure = JwtVerificationFailure(reason);
      expect(failure.toString(), equals('JwtVerificationFailure: $reason'));
    });
  });
}

// ignore_for_file: prefer_const_constructors
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:http/http.dart';
import 'package:jwt/jwt.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  const token =
      '''eyJhbGciOiJSUzI1NiIsImtpZCI6ImMxMGM5MGJhNGMzNjYzNTE2ZTA3MDdkMGU5YTg5NDgxMDYyODUxNTgiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL3NlY3VyZXRva2VuLmdvb2dsZS5jb20vbXktYXBwIiwiYXVkIjoibXktYXBwIiwiYXV0aF90aW1lIjoxNjQzNjg0MjY2LCJ1c2VyX2lkIjoiRzR1MzdXdk90dmVWR0pRb1pCWGpxcHVWazZWMiIsInN1YiI6Ikc0dTM3V3ZPdHZlVkdKUW9aQlhqcXB1Vms2VjIiLCJpYXQiOjE2NDM2ODQyNjYsImV4cCI6MTY0MzY4Nzg2NiwiZW1haWwiOiJ0ZXN0QGdtYWlsLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJmaXJlYmFzZSI6eyJpZGVudGl0aWVzIjp7ImVtYWlsIjpbInRlc3RAZ21haWwuY29tIl19LCJzaWduX2luX3Byb3ZpZGVyIjoicGFzc3dvcmQifX0.bUWnX_XmR1d9EmeFeYSsK_CHU1u9NPIHgyaQueZ6urYOtxvuL_QodjPl0c9CBJwctwPnxVyRmkeNCw0oF9xBgph0NApLL4FIG6vpDPZfW9txZBYr8xIvaqvmD0diACENAQdjRT2XmyEdQ2-U7SsTonybHmLoU9FMQTjAgw4NCALQvExfB6rtQ9GDsOBt1xoBkB3Vo7a5OmugZ1aHXF69b8As6137-Dggf5qx5R3oLRFovICMMesQziE3vGi-WKcbQxSeiD-9a6ShPAhk41XiyjFGDEOtUCQo63uwQnMw3g0KVtC6bzIyFq-E91vhxumxXzxPYC-kg7iUYiSZy7Y-Aw''';
  const tokenNoAuthTime =
      '''eyJhbGciOiJSUzI1NiIsImtpZCI6ImMxMGM5MGJhNGMzNjYzNTE2ZTA3MDdkMGU5YTg5NDgxMDYyODUxNTgiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL3NlY3VyZXRva2VuLmdvb2dsZS5jb20vbXktYXBwIiwiYXVkIjoibXktYXBwIiwidXNlcl9pZCI6Ikc0dTM3V3ZPdHZlVkdKUW9aQlhqcXB1Vms2VjIiLCJzdWIiOiJHNHUzN1d2T3R2ZVZHSlFvWkJYanFwdVZrNlYyIiwiaWF0IjoxNjQzNjg0MjY2LCJleHAiOjE2NDM2ODc4NjYsImVtYWlsIjoidGVzdEBnbWFpbC5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwiZmlyZWJhc2UiOnsiaWRlbnRpdGllcyI6eyJlbWFpbCI6WyJ0ZXN0QGdtYWlsLmNvbSJdfSwic2lnbl9pbl9wcm92aWRlciI6InBhc3N3b3JkIn19.ZWCadE43mUk43cPQdNCCi4WhDgB4ZsDT9rhPGQq_1uFPhzkVrCSRcjUhwkzH11VLap_MVurNvI_pGWbu9Z4CRPvGFzXPpuNveWy2qFPEa4jcM-R40vsbrP30vNnrp4PrmqgLar0vWs6FZ2g9fbjU8L1LaU5ik31OKSXufTIKn_hPHhyIC33tYTpWzG3Abq3H9EELHUXKW9nEcN8YYnOHAZ3A6ymb3DyBguhf2O-XAIlrn1WoxRRqlukFGSmprk7heonbVUTzoc3sIDZcC-Cj1U9wTee1NmqmU7v3SvpBRGnuXz-5rzSRHblyVxn_EEfCYwjsDUwetYpyFcCs5dqPlQ''';
  const keyValuePublicKeysUrl =
      'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';
  const jwkPublicKeysUrl =
      'https://login.microsoftonline.com/common/discovery/v2.0/keys';
  final jwkKeyStoreJsonString =
      File(p.join('test', 'fixtures', 'jwk_key_store.json')).readAsStringSync();
  final keyValueKeyStoreString =
      File(p.join('test', 'fixtures', 'key_value_key_store.json'))
          .readAsStringSync();
  final expiresAt = DateTime.fromMillisecondsSinceEpoch(1643687866 * 1000);
  final validTime = expiresAt.subtract(Duration(minutes: 15));

  late String keyStoreResponseBody;

  setUp(() {
    getOverride = (Uri uri) async {
      return Response(
        keyStoreResponseBody,
        HttpStatus.ok,
        headers: {'cache-control': 'max-age=3600'},
      );
    };
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

      test('throws a JwtVerificationFailure if string is not valid jwt',
          () async {
        await expectLater(
          () => verify(
            'not.a.jwt',
            audience: {audience},
            issuer: issuer,
            publicKeysUrl: keyValuePublicKeysUrl,
          ),
          throwsA(
            isA<JwtVerificationFailure>().having(
              (e) => e.reason,
              'reason',
              'JWT header is malformed.',
            ),
          ),
        );
      });

      test('can verify an invalid audience', () async {
        await withClock(Clock.fixed(validTime), () async {
          try {
            await verify(
              token,
              audience: {'invalid-audience'},
              issuer: issuer,
              publicKeysUrl: keyValuePublicKeysUrl,
            );
            fail('should throw');
          } catch (error) {
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
            );
            fail('should throw');
          } catch (error) {
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
          );
          expect(jwt, isA<Jwt>());
        });
      });

      group('when key store is JWK store', () {
        const token =
            '''eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6InRSNHdrWWhIeEhvX3FlcHJTMDhDdXc4eGNPdyJ9.eyJ2ZXIiOiIyLjAiLCJpc3MiOiJodHRwczovL2xvZ2luLm1pY3Jvc29mdG9ubGluZS5jb20vOTE4ODA0MGQtNmM2Ny00YzViLWIxMTItMzZhMzA0YjY2ZGFkL3YyLjAiLCJzdWIiOiJBQUFBQUFBQUFBQUFBQUFBQUFBQUFKclpOMmI0eldUNzhQWFJEN2J6dkxrIiwiYXVkIjoiYzRhZjk1NjYtOGEzNi00MzQ4LWI0MTMtZGFiNjY1Yjg3MTdkIiwiZXhwIjoxNzA4NTQ2MDYwLCJpYXQiOjE3MDg0NTkzNjAsIm5iZiI6MTcwODQ1OTM2MCwiZW1haWwiOiJicnlhbm9sdG1hbkBob3RtYWlsLmNvbSIsInRpZCI6IjkxODgwNDBkLTZjNjctNGM1Yi1iMTEyLTM2YTMwNGI2NmRhZCIsImFpbyI6IkRtUE91OTNxdWlSNm9OYVBrMjl1dVFSTkhSN0NIS0V4VDlrSE5DamVJIUdpN3JMQks2SDZYYzdkUWl2ZmRxTVZ5VExuNDMxUWRaTXpPSHQqaDQ2NWViQTlBWE9RdzhOdlM3dzNTbFREWU9iOW52OGh2SHNDTXZqdlJJMzRaWXlPbiE2MHBUcXghWnVmeTF0VnRGMWp6VEVsQmlUTjRrOWJIU0RDUFZaU1BlaXNzYjFLdmhCamc4biFPUSptNWszSmZ3JCQifQ.PhZfpmMmhlW_w9P-EQjcA-DgD0Mxnufxgn6rsKlQYtRn2hmT8uGOlMpMthYIeYLhVPtQqPyHDdW-0GxJ3ROK6prlogvPt8SxY8lSiJ6a4XCNmGop-7MxWGkYhqnMw21TKiSsGIr5LSuD3b_5RK6uBipra0rf819Wlvp6JbXulGSHt9N_qyq8328npCHRYbIDOBcOgDjnPjDFp_pJ99-itCsM8OO0npZJZ64MmlENgEYswnOQYlCShF1HLQwes7uGuw8ZBik-XSu44iJKJ9u4Ai3BjpxYdMFmMZ-B4DpF3uWpFsK-X9tMbi23gwufu5X_6aqtZYRLg052M1SUaBiMUw''';
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
            );
            expect(jwt, isA<Jwt>());
          });
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
      final failure = JwtVerificationFailure(reason);
      expect(failure.toString(), equals('JwtVerificationFailure: $reason'));
    });
  });
}

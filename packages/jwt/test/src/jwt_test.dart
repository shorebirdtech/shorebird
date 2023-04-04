// ignore_for_file: prefer_const_constructors
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:http/http.dart';
import 'package:jwt/jwt.dart';
import 'package:test/test.dart';

void main() {
  const token =
      '''eyJhbGciOiJSUzI1NiIsImtpZCI6ImMxMGM5MGJhNGMzNjYzNTE2ZTA3MDdkMGU5YTg5NDgxMDYyODUxNTgiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL3NlY3VyZXRva2VuLmdvb2dsZS5jb20vbXktYXBwIiwiYXVkIjoibXktYXBwIiwiYXV0aF90aW1lIjoxNjQzNjg0MjY2LCJ1c2VyX2lkIjoiRzR1MzdXdk90dmVWR0pRb1pCWGpxcHVWazZWMiIsInN1YiI6Ikc0dTM3V3ZPdHZlVkdKUW9aQlhqcXB1Vms2VjIiLCJpYXQiOjE2NDM2ODQyNjYsImV4cCI6MTY0MzY4Nzg2NiwiZW1haWwiOiJ0ZXN0QGdtYWlsLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJmaXJlYmFzZSI6eyJpZGVudGl0aWVzIjp7ImVtYWlsIjpbInRlc3RAZ21haWwuY29tIl19LCJzaWduX2luX3Byb3ZpZGVyIjoicGFzc3dvcmQifX0.bUWnX_XmR1d9EmeFeYSsK_CHU1u9NPIHgyaQueZ6urYOtxvuL_QodjPl0c9CBJwctwPnxVyRmkeNCw0oF9xBgph0NApLL4FIG6vpDPZfW9txZBYr8xIvaqvmD0diACENAQdjRT2XmyEdQ2-U7SsTonybHmLoU9FMQTjAgw4NCALQvExfB6rtQ9GDsOBt1xoBkB3Vo7a5OmugZ1aHXF69b8As6137-Dggf5qx5R3oLRFovICMMesQziE3vGi-WKcbQxSeiD-9a6ShPAhk41XiyjFGDEOtUCQo63uwQnMw3g0KVtC6bzIyFq-E91vhxumxXzxPYC-kg7iUYiSZy7Y-Aw''';
  const publicKeysUrl =
      'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';
  const issuer = 'https://securetoken.google.com/my-app';
  const audience = 'my-app';
  final publicKey = File('test/fixtures/public_key.pem').readAsStringSync();
  final body = json.encode(
    {'c10c90ba4c3663516e0707d0e9a8948106285158': publicKey},
  );
  final expiresAt = DateTime.fromMillisecondsSinceEpoch(1643687866 * 1000);
  final validTime = expiresAt.subtract(Duration(minutes: 15));

  group('verify', () {
    test('can be instantiated', () {
      expect(verify, isNotNull);
    });

    test('can verify an expired jwt', () async {
      getOverride = (Uri uri) async {
        return Response(
          body,
          HttpStatus.ok,
          headers: {'cache-control': 'max-age=3600'},
        );
      };

      try {
        await verify(
          token,
          audience: audience,
          issuer: issuer,
          publicKeysUrl: publicKeysUrl,
        );
        fail('should throw');
      } catch (error) {
        expect(
          error,
          isA<JwtVerificationFailure>().having(
            (e) => e.reason,
            'reason',
            'Token has expired.',
          ),
        );
      }
    });

    test('can verify an invalid audience', () async {
      await withClock(Clock.fixed(validTime), () async {
        getOverride = (Uri uri) async {
          return Response(
            body,
            HttpStatus.ok,
            headers: {'cache-control': 'max-age=3600'},
          );
        };
        try {
          await verify(
            token,
            audience: 'invalid-audience',
            issuer: issuer,
            publicKeysUrl: publicKeysUrl,
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
        getOverride = (Uri uri) async {
          return Response(
            body,
            HttpStatus.ok,
            headers: {'cache-control': 'max-age=3600'},
          );
        };
        try {
          await verify(
            token,
            audience: audience,
            issuer: 'https://invalid/issuer',
            publicKeysUrl: publicKeysUrl,
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
        getOverride = (Uri uri) async {
          return Response(
            body,
            HttpStatus.ok,
            headers: {'cache-control': 'max-age=3600'},
          );
        };
        final jwt = await verify(
          token,
          audience: audience,
          issuer: issuer,
          publicKeysUrl: publicKeysUrl,
        );
        expect(jwt, isA<Jwt>());
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

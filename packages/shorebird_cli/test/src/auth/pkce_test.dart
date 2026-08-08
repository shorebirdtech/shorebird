import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shorebird_cli/src/auth/pkce.dart';
import 'package:test/test.dart';

void main() {
  group(PkcePair, () {
    test('derives the challenge as base64url(sha256(verifier))', () {
      final pair = PkcePair.generate();
      final expected = base64UrlEncode(
        sha256.convert(utf8.encode(pair.verifier)).bytes,
      ).replaceAll('=', '');
      expect(pair.challenge, equals(expected));
    });

    test('produces a verifier within the RFC 7636 length bounds', () {
      final pair = PkcePair.generate();
      expect(pair.verifier.length, greaterThanOrEqualTo(43));
      expect(pair.verifier.length, lessThanOrEqualTo(128));
    });

    test('produces a 43-character challenge', () {
      // A SHA-256 digest is 32 bytes, exactly 43 unpadded base64url
      // characters, which is the length the auth service validates.
      expect(PkcePair.generate().challenge.length, equals(43));
    });

    test('emits unpadded base64url only', () {
      // The auth service checks both values against the unreserved character
      // set, so `+`, `/`, and `=` would be rejected.
      final unreserved = RegExp(r'^[A-Za-z0-9\-._~]+$');
      final pair = PkcePair.generate();
      expect(unreserved.hasMatch(pair.verifier), isTrue);
      expect(unreserved.hasMatch(pair.challenge), isTrue);
    });

    test('generates a distinct verifier per call', () {
      final verifiers = List.generate(50, (_) => PkcePair.generate().verifier);
      expect(verifiers.toSet(), hasLength(50));
    });
  });
}

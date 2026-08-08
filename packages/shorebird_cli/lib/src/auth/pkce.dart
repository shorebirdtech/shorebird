import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// A PKCE (RFC 7636) verifier and the S256 challenge derived from it.
///
/// The CLI is a public OAuth client: it holds no secret, and it receives its
/// authorization code on a loopback redirect. Anything able to observe that
/// redirect — another process that binds the callback port first, a browser
/// extension, a shell history dump — could otherwise replay the code against
/// the auth service and obtain a full session.
///
/// PKCE binds the code to [verifier], which stays in this process until the
/// token exchange. A stolen code is useless without it.
@immutable
class PkcePair {
  const PkcePair._({required this.verifier, required this.challenge});

  /// Generates a fresh pair from a cryptographically secure source.
  factory PkcePair.generate() {
    // 32 random bytes encode to 43 base64url characters, the shortest verifier
    // RFC 7636 section 4.1 permits and the exact length of an S256 challenge.
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final verifier = _base64Url(bytes);
    return PkcePair._(
      verifier: verifier,
      challenge: _base64Url(sha256.convert(utf8.encode(verifier)).bytes),
    );
  }

  /// The secret held by this process, sent only in the token exchange.
  final String verifier;

  /// `BASE64URL(SHA256(verifier))`, sent in the authorization request.
  final String challenge;

  /// RFC 7636 requires unpadded base64url for both values; `base64UrlEncode`
  /// pads.
  static String _base64Url(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');
}

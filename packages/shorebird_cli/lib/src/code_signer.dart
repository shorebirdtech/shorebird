import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pem/pem.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// A reference to a [CodeSigner] instance.
final codeSignerRef = create(CodeSigner.new);

/// The [CodeSigner] instance available in the current zone.
CodeSigner get codeSigner => read(codeSignerRef);

/// {@template code_signer}
/// Manages code signing operations.
/// {@endtemplate}
class CodeSigner {
  /// Signs a [message] using the provided [privateKeyPemFile] using
  /// SHA-256/RSA.
  ///
  /// This is the equivalent of:
  ///   $ openssl dgst -sha256 -sign privateKey.pem -out signature message
  String sign({required String message, required File privateKeyPemFile}) {
    final privateKeyData = _privateKeyBytes(pemFile: privateKeyPemFile);
    final privateKey = RSAPrivateKeyFromInt.from(privateKeyData);

    final signer = Signer('SHA-256/RSA')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

    final signature =
        signer.generateSignature(utf8.encode(message)) as RSASignature;
    return base64.encode(signature.bytes);
  }

  /// Decodes a PEM file containing a private and returns its contents as bytes.
  List<int> _privateKeyBytes({required File pemFile}) {
    final privateKeyString = pemFile.readAsStringSync();
    final pemCodec = PemCodec(PemLabel.privateKey);
    return pemCodec.decode(privateKeyString);
  }
}

extension RSAPrivateKeyFromInt on RSAPrivateKey {
  /// Converts an RSA private key bytes to a pointycastle [RSAPrivateKey].
  ///
  /// Based on https://github.com/konstantinullrich/crypton/blob/trunk/lib/src/rsa/private_key.dart
  static RSAPrivateKey from(List<int> privateKeyBytes) {
    var asn1Parser = ASN1Parser(Uint8List.fromList(privateKeyBytes));
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    final privateKey = topLevelSeq.elements![2];

    asn1Parser = ASN1Parser(privateKey.valueBytes);
    final pkSeq = asn1Parser.nextObject() as ASN1Sequence;

    final modulus = pkSeq.elements![1] as ASN1Integer;
    final privateExponent = pkSeq.elements![3] as ASN1Integer;
    final p = pkSeq.elements![4] as ASN1Integer;
    final q = pkSeq.elements![5] as ASN1Integer;

    return RSAPrivateKey(
      modulus.integer!,
      privateExponent.integer!,
      p.integer,
      q.integer,
    );
  }
}

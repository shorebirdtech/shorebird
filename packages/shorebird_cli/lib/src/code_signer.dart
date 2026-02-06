// cspell:words dgst
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pem/pem.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

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
    final privateKeyData = _pemBytes(
      pemFile: privateKeyPemFile,
      type: PemLabel.privateKey,
    );
    final privateKey = _RSAPrivateKeyFromBytes.from(privateKeyData);

    final signer = Signer('SHA-256/RSA')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

    final signature =
        signer.generateSignature(utf8.encode(message)) as RSASignature;
    return base64.encode(signature.bytes);
  }

  /// Extracts the base64 encoded DER from a public key PEM file. The DER is
  /// simply the modulus and exponent of the public key, without information
  /// about the algorithm or or ASN1 object type identifier.
  String base64PublicKey(File publicKeyPemFile) {
    final publicKey = _RSAPublicKeyFromBytes.rsaPublicKeyFromBytes(
      _pemBytes(pemFile: publicKeyPemFile, type: PemLabel.publicKey),
    );

    final publicKeySeq = ASN1Sequence()
      ..add(ASN1Integer(publicKey.modulus))
      ..add(ASN1Integer(publicKey.exponent))
      ..encode();
    return base64.encode(publicKeySeq.encodedBytes!);
  }

  /// Extracts the base64 encoded DER from a PEM-encoded public key string.
  String base64PublicKeyFromPem(String publicKeyPem) {
    final publicKey = _RSAPublicKeyFromBytes.rsaPublicKeyFromBytes(
      PemCodec(PemLabel.publicKey).decode(publicKeyPem),
    );

    final publicKeySeq = ASN1Sequence()
      ..add(ASN1Integer(publicKey.modulus))
      ..add(ASN1Integer(publicKey.exponent))
      ..encode();
    return base64.encode(publicKeySeq.encodedBytes!);
  }

  /// Runs a command and returns its stdout, expected to be a PEM public key.
  Future<String> runPublicKeyCmd(String command) async {
    final result = await process.run(
      'sh',
      ['-c', command],
      runInShell: true,
    );

    if (result.exitCode != 0) {
      throw ProcessException(
        command,
        [],
        'Command failed with exit code ${result.exitCode}: ${result.stderr}',
        result.exitCode,
      );
    }

    final output = '${result.stdout}'.trim();
    if (!output.contains('-----BEGIN') || !output.contains('PUBLIC KEY')) {
      throw FormatException(
        'Command output does not appear to be a PEM-encoded public key: '
        '${output.substring(0, output.length.clamp(0, 100))}...',
      );
    }

    return output;
  }

  /// Signs data by piping it to a command's stdin and reading the base64
  /// signature from stdout.
  Future<String> signWithCmd({
    required String data,
    required String command,
  }) async {
    final proc = await process.start(
      'sh',
      ['-c', command],
    );

    // Write data to stdin and close it
    proc.stdin.write(data);
    await proc.stdin.close();

    // Read stdout as the signature
    final stdout = await proc.stdout.transform(utf8.decoder).join();
    final stderr = await proc.stderr.transform(utf8.decoder).join();
    final exitCode = await proc.exitCode;

    if (exitCode != 0) {
      throw ProcessException(
        command,
        [],
        'Sign command failed with exit code $exitCode: $stderr',
        exitCode,
      );
    }

    final signature = stdout.trim();
    if (signature.isEmpty) {
      throw const FormatException('Sign command produced no output');
    }

    return signature;
  }

  /// Verifies a signature against a message using a PEM-encoded public key.
  bool verify({
    required String message,
    required String signature,
    required String publicKeyPem,
  }) {
    final publicKey = _RSAPublicKeyFromBytes.rsaPublicKeyFromBytes(
      PemCodec(PemLabel.publicKey).decode(publicKeyPem),
    );

    final signer = Signer('SHA-256/RSA')
      ..init(false, PublicKeyParameter<RSAPublicKey>(publicKey));

    try {
      return signer.verifySignature(
        utf8.encode(message),
        RSASignature(base64.decode(signature)),
      );
    } on Exception {
      return false;
    }
  }

  /// Reads a PEM file containing a key of type [type] and returns its contents
  /// as bytes.
  List<int> _pemBytes({required File pemFile, required PemLabel type}) {
    final privateKeyString = pemFile.readAsStringSync();
    return PemCodec(type).decode(privateKeyString);
  }
}

extension _RSAPrivateKeyFromBytes on RSAPrivateKey {
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

extension _RSAPublicKeyFromBytes on RSAPublicKey {
  /// Converts an RSA public key to a pointycastle [RSAPublicKey].
  ///
  /// Based on https://github.com/Ephenodrom/Dart-Basic-Utils/blob/45ed0a3087b2051004f17b39eb5289874b9c0390/lib/src/CryptoUtils.dart#L525-L547
  static RSAPublicKey rsaPublicKeyFromBytes(List<int> bytes) {
    final asn1Parser = ASN1Parser(Uint8List.fromList(bytes));
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    final publicKeyBitString = topLevelSeq.elements![1] as ASN1BitString;
    final publicKeyAsn = ASN1Parser(
      publicKeyBitString.stringValues as Uint8List?,
    );
    final publicKeySeq = publicKeyAsn.nextObject() as ASN1Sequence;
    final modulus = publicKeySeq.elements![0] as ASN1Integer;
    final exponent = publicKeySeq.elements![1] as ASN1Integer;

    return RSAPublicKey(modulus.integer!, exponent.integer!);
  }
}

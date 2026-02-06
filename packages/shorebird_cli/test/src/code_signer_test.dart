// cspell:words pubin dgst outform
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:test/test.dart';

void main() {
  group(
    CodeSigner,
    () {
      final cryptoFixturesBasePath = p.join('test', 'fixtures', 'crypto');
      // PKCS#8 format (BEGIN PRIVATE KEY)
      final privateKeyFile = File(
        p.join(cryptoFixturesBasePath, 'private.pem'),
      );
      // PKCS#1 format (BEGIN RSA PRIVATE KEY)
      final privateKeyPkcs1File = File(
        p.join(cryptoFixturesBasePath, 'private_pkcs1.pem'),
      );
      final publicKeyFile = File(p.join(cryptoFixturesBasePath, 'public.pem'));

      late CodeSigner codeSigner;

      setUp(() {
        codeSigner = CodeSigner();
      });

      group('sign', () {
        const message =
            '6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b';

        test('signature matches openssl output with PKCS#8 key', () async {
          final outputDir = Directory.systemTemp.createTempSync();
          final messageFile = File(p.join(outputDir.path, 'message'))
            ..writeAsStringSync(message);
          final signatureFile = File(p.join(outputDir.path, 'signature'));
          await Process.run('openssl', [
            'dgst',
            '-sha256',
            '-sign',
            privateKeyFile.path,
            '-out',
            signatureFile.path,
            messageFile.path,
          ]);

          final expectedSignature = base64Encode(
            signatureFile.readAsBytesSync(),
          );
          final actualSignature = codeSigner.sign(
            message: message,
            privateKeyPemFile: privateKeyFile,
          );
          expect(actualSignature, equals(expectedSignature));
        });

        test('signature matches openssl output with PKCS#1 key', () async {
          final outputDir = Directory.systemTemp.createTempSync();
          final messageFile = File(p.join(outputDir.path, 'message'))
            ..writeAsStringSync(message);
          final signatureFile = File(p.join(outputDir.path, 'signature'));
          await Process.run('openssl', [
            'dgst',
            '-sha256',
            '-sign',
            privateKeyPkcs1File.path,
            '-out',
            signatureFile.path,
            messageFile.path,
          ]);

          final expectedSignature = base64Encode(
            signatureFile.readAsBytesSync(),
          );
          final actualSignature = codeSigner.sign(
            message: message,
            privateKeyPemFile: privateKeyPkcs1File,
          );
          expect(actualSignature, equals(expectedSignature));
        });

        test('PKCS#1 and PKCS#8 keys produce identical signatures', () {
          // Both keys are derived from the same RSA key pair, so they should
          // produce the same signature.
          final pkcs8Signature = codeSigner.sign(
            message: message,
            privateKeyPemFile: privateKeyFile,
          );
          final pkcs1Signature = codeSigner.sign(
            message: message,
            privateKeyPemFile: privateKeyPkcs1File,
          );
          expect(pkcs1Signature, equals(pkcs8Signature));
        });
      });

      group('base64PublicKey', () {
        test('output matches equivalent openssl command', () async {
          final tempDir = Directory.systemTemp.createTempSync();
          final expectedDerFile = File(p.join(tempDir.path, 'public.der'));
          await Process.run('openssl', [
            'rsa',
            '-pubin',
            '-in',
            publicKeyFile.path,
            '-inform',
            'PEM',
            '-RSAPublicKey_out',
            '-outform',
            'DER',
            '-out',
            expectedDerFile.path,
          ]);
          expect(
            codeSigner.base64PublicKey(publicKeyFile),
            equals(base64Encode(expectedDerFile.readAsBytesSync())),
          );
        });
      });
    },
    onPlatform: {
      'windows': const Skip('Does not have openssl installed by default'),
    },
  );
}

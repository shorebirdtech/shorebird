// cspell:words pubin dgst outform
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'mocks.dart';

void main() {
  useTempWorkingDirectory();
  group(
    CodeSigner,
    () {
      final cryptoFixturesBasePath = p.join(fixturesDirectory, 'crypto');
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

      group('canonicalPublicKeyPem', () {
        Matcher refusedWithout(String keyText) => throwsA(
          isA<InvalidPublicKeyException>()
              .having((e) => e.source, 'source', isNull)
              .having((e) => '$e', 'toString', isNot(contains(keyText))),
        );
        String bodyLine(File file) => const LineSplitter()
            .convert(file.readAsStringSync())
            .firstWhere((line) => !line.startsWith('-----'));

        test('returns the same key, re-encoded', () {
          final publicKey = publicKeyFile.readAsStringSync();
          final canonical = codeSigner.canonicalPublicKeyPem(publicKey);

          expect(canonical, startsWith('-----BEGIN PUBLIC KEY-----'));
          expect(
            codeSigner.base64PublicKeyFromPem(canonical),
            codeSigner.base64PublicKeyFromPem(publicKey),
          );
          // Wrapping and line endings do not change it.
          expect(
            codeSigner.canonicalPublicKeyPem(
              '\n${publicKey.replaceAll('\n', '\r\n')}\n',
            ),
            canonical,
          );
        });

        test('refuses data hidden in the block', () {
          final publicKey = publicKeyFile.readAsStringSync();
          final privateBody = const LineSplitter()
              .convert(privateKeyFile.readAsStringSync())
              .where((line) => !line.startsWith('-----'))
              .join('\n');
          final body = const LineSplitter()
              .convert(publicKey)
              .where((line) => !line.startsWith('-----'))
              .join('\n');
          const begin = '-----BEGIN PUBLIC KEY-----';
          const end = '-----END PUBLIC KEY-----';
          for (final pem in [
            // A private key's body after the public key's.
            '$begin\n$body\n$privateBody\n$end\n',
            // A second END line with the private key's body between.
            '$publicKey$privateBody\n-----END PUBLIC KEY-----\n',
          ]) {
            expect(
              () => codeSigner.canonicalPublicKeyPem(pem),
              refusedWithout(privateBody.substring(0, 40)),
            );
          }
        });

        test('refuses a key that is not RSA', () {
          // An Ed25519 SubjectPublicKeyInfo.
          expect(
            () => codeSigner.canonicalPublicKeyPem(
              '-----BEGIN PUBLIC KEY-----\n'
              'MCowBQYDK2VwAyEAGb9ECWmEzf6FQbrBZ9w7lshQhqowtrbLDFw4rXAxZuE=\n'
              '-----END PUBLIC KEY-----\n',
            ),
            throwsA(
              isA<InvalidPublicKeyException>().having(
                (e) => e.message,
                'message',
                startsWith('is not an RSA public key'),
              ),
            ),
          );
        });

        test('refuses a block that is not a key', () {
          expect(
            () => codeSigner.canonicalPublicKeyPem(
              '-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----\n',
            ),
            throwsA(
              isA<InvalidPublicKeyException>()
                  .having(
                    (e) => e.message,
                    'message',
                    'is not a valid public key.',
                  )
                  .having((e) => e.source, 'source', isNull),
            ),
          );
        });

        for (final file in [privateKeyFile, privateKeyPkcs1File]) {
          test('refuses ${p.basename(file.path)} without quoting it', () {
            expect(
              () => codeSigner.canonicalPublicKeyPem(file.readAsStringSync()),
              refusedWithout(bodyLine(file)),
            );
            expect(
              () => codeSigner.canonicalPublicKeyPem(file.readAsStringSync()),
              throwsA(
                isA<InvalidPublicKeyException>().having(
                  (e) => e.message,
                  'message',
                  startsWith('contains a private key.'),
                ),
              ),
            );
          });
        }

        test('refuses a public key alongside a private one', () {
          expect(
            () => codeSigner.canonicalPublicKeyPem(
              '${publicKeyFile.readAsStringSync()}'
              '${privateKeyFile.readAsStringSync()}',
            ),
            refusedWithout(bodyLine(privateKeyFile)),
          );
        });

        test('refuses anything but exactly one public key', () {
          final publicKey = publicKeyFile.readAsStringSync();
          for (final pem in [
            '',
            'not a key',
            '$publicKey$publicKey',
            'key:\n$publicKey',
            publicKey.replaceAll('PUBLIC KEY', 'RSA PUBLIC KEY'),
          ]) {
            expect(
              () => codeSigner.canonicalPublicKeyPem(pem),
              throwsA(
                isA<InvalidPublicKeyException>().having(
                  (e) => e.message,
                  'message',
                  startsWith('must contain exactly one PEM public key'),
                ),
              ),
              reason: pem,
            );
          }
        });
      });

      group('base64PublicKeyFromPem', () {
        test('output matches base64PublicKey from file', () {
          final publicKeyPem = publicKeyFile.readAsStringSync();
          expect(
            codeSigner.base64PublicKeyFromPem(publicKeyPem),
            equals(codeSigner.base64PublicKey(publicKeyFile)),
          );
        });
      });

      group('verify', () {
        const message =
            '6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b';

        test('returns true for valid signature', () {
          final signature = codeSigner.sign(
            message: message,
            privateKeyPemFile: privateKeyFile,
          );
          final publicKeyPem = publicKeyFile.readAsStringSync();

          expect(
            codeSigner.verify(
              message: message,
              signature: signature,
              publicKeyPem: publicKeyPem,
            ),
            isTrue,
          );
        });

        test('returns false for invalid signature', () {
          final publicKeyPem = publicKeyFile.readAsStringSync();

          expect(
            codeSigner.verify(
              message: message,
              signature: 'invalid-signature',
              publicKeyPem: publicKeyPem,
            ),
            isFalse,
          );
        });

        test('returns false for wrong message', () {
          final signature = codeSigner.sign(
            message: message,
            privateKeyPemFile: privateKeyFile,
          );
          final publicKeyPem = publicKeyFile.readAsStringSync();

          expect(
            codeSigner.verify(
              message: 'wrong-message',
              signature: signature,
              publicKeyPem: publicKeyPem,
            ),
            isFalse,
          );
        });
      });
    },
    onPlatform: {
      'windows': const Skip('Does not have openssl installed by default'),
    },
  );

  group('CodeSigner command-based signing', () {
    late ShorebirdProcess shorebirdProcess;
    late CodeSigner codeSigner;

    setUp(() {
      shorebirdProcess = MockShorebirdProcess();
      codeSigner = CodeSigner();
    });

    group('runPublicKeyCmd', () {
      test('returns trimmed stdout on success', () async {
        final result = MockShorebirdProcessResult();
        when(() => result.exitCode).thenReturn(0);
        when(() => result.stdout).thenReturn('''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
-----END PUBLIC KEY-----
''');
        when(
          () => shorebirdProcess.run(any(), any()),
        ).thenAnswer((_) async => result);

        await runScoped(
          () async {
            final output = await codeSigner.runPublicKeyCmd('cat key.pem');
            expect(output, contains('-----BEGIN PUBLIC KEY-----'));
            expect(output, contains('-----END PUBLIC KEY-----'));
          },
          values: {processRef.overrideWith(() => shorebirdProcess)},
        );
      });

      test('throws ProcessException on non-zero exit code', () async {
        final result = MockShorebirdProcessResult();
        when(() => result.exitCode).thenReturn(1);
        when(() => result.stderr).thenReturn('command not found');
        when(
          () => shorebirdProcess.run(any(), any()),
        ).thenAnswer((_) async => result);

        await runScoped(
          () async {
            await expectLater(
              () => codeSigner.runPublicKeyCmd('invalid-command'),
              throwsA(isA<ProcessException>()),
            );
          },
          values: {processRef.overrideWith(() => shorebirdProcess)},
        );
      });

      test('refuses empty output', () async {
        final result = MockShorebirdProcessResult();
        when(() => result.exitCode).thenReturn(0);
        when(() => result.stdout).thenReturn('');
        when(
          () => shorebirdProcess.run(any(), any()),
        ).thenAnswer((_) async => result);

        await runScoped(
          () async {
            await expectLater(
              () => codeSigner.runPublicKeyCmd('empty-cmd'),
              throwsA(
                isA<InvalidPublicKeyException>().having(
                  (e) => e.message,
                  'message',
                  startsWith('is empty.'),
                ),
              ),
            );
          },
          values: {processRef.overrideWith(() => shorebirdProcess)},
        );
      });

      test('refuses a private key without echoing it', () async {
        final privateKey = File(
          p.join(fixturesDirectory, 'crypto', 'private.pem'),
        ).readAsStringSync();
        final keyLine = const LineSplitter()
            .convert(privateKey)
            .firstWhere((line) => !line.startsWith('-----'));
        final result = MockShorebirdProcessResult();
        when(() => result.exitCode).thenReturn(0);
        when(() => result.stdout).thenReturn(privateKey);
        when(
          () => shorebirdProcess.run(any(), any()),
        ).thenAnswer((_) async => result);

        await runScoped(
          () async {
            final returned = await codeSigner.runPublicKeyCmd(
              'cat private.pem',
            );
            expect(
              () => codeSigner.canonicalPublicKeyPem(returned),
              throwsA(
                isA<InvalidPublicKeyException>()
                    .having(
                      (e) => e.message,
                      'message',
                      startsWith('contains a private key.'),
                    )
                    .having((e) => '$e', 'toString', isNot(contains(keyLine))),
              ),
            );
          },
          values: {processRef.overrideWith(() => shorebirdProcess)},
        );
      });

      test('never quotes output that is not a public key', () async {
        // A raw EC private key in base64, which no PEM check recognizes.
        const output = 'MHcCAQEEIBaUw8nMbFNd7SHfQyw0OprZQNiGn9Ag1RCLo3mQ9hRx';
        final result = MockShorebirdProcessResult();
        when(() => result.exitCode).thenReturn(0);
        when(() => result.stdout).thenReturn(output);
        when(
          () => shorebirdProcess.run(any(), any()),
        ).thenAnswer((_) async => result);

        await runScoped(
          () async {
            final returned = await codeSigner.runPublicKeyCmd('print-key');
            expect(
              () => codeSigner.canonicalPublicKeyPem(returned),
              throwsA(
                isA<InvalidPublicKeyException>()
                    .having((e) => '$e', 'toString', isNot(contains(output)))
                    .having((e) => e.source, 'source', isNull),
              ),
            );
          },
          values: {processRef.overrideWith(() => shorebirdProcess)},
        );
      });
    });

    group('signWithCmd', () {
      late MockProcess proc;
      late MockIOSink stdin;

      setUp(() {
        proc = MockProcess();
        stdin = MockIOSink();
        when(() => proc.stdin).thenReturn(stdin);
        when(() => stdin.close()).thenAnswer((_) async {});
      });

      test('returns trimmed stdout on success', () async {
        when(() => proc.stdout).thenAnswer(
          (_) => Stream.value(utf8.encode('base64signature\n')),
        );
        when(() => proc.stderr).thenAnswer((_) => const Stream.empty());
        when(() => proc.exitCode).thenAnswer((_) async => 0);
        when(
          () => shorebirdProcess.start(any(), any()),
        ).thenAnswer((_) async => proc);

        await runScoped(
          () async {
            final signature = await codeSigner.signWithCmd(
              data: 'hash-to-sign',
              command: 'sign-script.sh',
            );
            expect(signature, equals('base64signature'));
          },
          values: {processRef.overrideWith(() => shorebirdProcess)},
        );
      });

      test('throws ProcessException on non-zero exit code', () async {
        when(() => proc.stdout).thenAnswer((_) => const Stream.empty());
        when(() => proc.stderr).thenAnswer(
          (_) => Stream.value(utf8.encode('error')),
        );
        when(() => proc.exitCode).thenAnswer((_) async => 1);
        when(
          () => shorebirdProcess.start(any(), any()),
        ).thenAnswer((_) async => proc);

        await runScoped(
          () async {
            await expectLater(
              () => codeSigner.signWithCmd(
                data: 'hash-to-sign',
                command: 'failing-script.sh',
              ),
              throwsA(isA<ProcessException>()),
            );
          },
          values: {processRef.overrideWith(() => shorebirdProcess)},
        );
      });

      test('refuses empty output', () async {
        when(() => proc.stdout).thenAnswer(
          (_) => Stream.value(utf8.encode('  \n  ')),
        );
        when(() => proc.stderr).thenAnswer((_) => const Stream.empty());
        when(() => proc.exitCode).thenAnswer((_) async => 0);
        when(
          () => shorebirdProcess.start(any(), any()),
        ).thenAnswer((_) async => proc);

        await runScoped(
          () async {
            await expectLater(
              () => codeSigner.signWithCmd(
                data: 'hash-to-sign',
                command: 'empty-output-script.sh',
              ),
              throwsA(isA<FormatException>()),
            );
          },
          values: {processRef.overrideWith(() => shorebirdProcess)},
        );
      });
    });
  });
}

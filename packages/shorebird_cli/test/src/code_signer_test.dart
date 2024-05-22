import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:test/test.dart';

void main() {
  group(
    CodeSigner,
    () {
      final cryptoFixturesBasePath = p.join('test', 'fixtures', 'crypto');
      final privateKeyFile =
          File(p.join(cryptoFixturesBasePath, 'private.pem'));

      late CodeSigner codeSigner;

      setUp(() {
        codeSigner = CodeSigner();
      });

      group('sign', () {
        const message =
            '6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b';
        test('signature matches openssl output', () async {
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

          final expectedSignature =
              base64Encode(signatureFile.readAsBytesSync());
          final actualSignature = codeSigner.sign(
            message: message,
            privateKeyPemFile: privateKeyFile,
          );
          expect(actualSignature, equals(expectedSignature));
        });
      });
    },
    onPlatform: {
      'windows': const Skip('Does not have openssl installed by default'),
    },
  );
}

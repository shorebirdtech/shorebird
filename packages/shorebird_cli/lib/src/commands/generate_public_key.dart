import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/extensions/file.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/io.dart';

/// {@template generate_public_key_command}
/// A command that creates a public key from a private key
/// in the format expected by the patch verification process.
/// {@endtemplate}
class GeneratePublicKeyCommand extends ShorebirdCommand {
  /// {@macro generate_public_key_command}
  GeneratePublicKeyCommand() {
    argParser
      ..addOption(
        'private-key',
        abbr: 'k',
        mandatory: true,
        help: 'The path from the private key to generate the public key from.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        mandatory: true,
        help: 'The destination path where the public key will be written to.',
      );
  }

  @override
  String get description => 'Takes a private key and generate a public key in '
      'the format expected by the signature verification process.';

  @override
  String get name => 'public_key';

  @override
  bool get hidden => true;

  @override
  FutureOr<int>? run() async {
    final privateKey = results.file('private-key');
    privateKey!.assertExists();

    final output = results['output'] as String;

    final pemFileProgress = logger.progress('🔑 Generating PEM key');
    final tempPemFile = File(
      p.join(
        Directory.systemTemp.createTempSync().path,
        '_shorebird_temp_public_key.pem',
      ),
    );

    // First generate a public key
    // openssl rsa -in private.pem -outform PEM -pubout -out public.pem
    final createKeyResult = await process.run(
      'openssl',
      [
        'rsa',
        '-in',
        privateKey.path,
        '-outform',
        'PEM',
        '-pubout',
        '-out',
        tempPemFile.path,
      ],
    );

    if (createKeyResult.exitCode != ExitCode.success.code) {
      pemFileProgress.fail('Error creating pem file');
      exit(ExitCode.software.code);
    }

    pemFileProgress.complete();

    final transformingKeyProgress = logger.progress(
      '🔐 Deriving key',
    );

    // Then get its derived format
    // openssl rsa -pubin \
    //         -in public_key.pem \
    //         -inform PEM \
    //         -RSAPublicKey_out \
    //         -outform DER \
    //         -out public_key.der

    final derivingResult = await process.run(
      'openssl',
      [
        'rsa',
        '-pubin',
        '-in',
        tempPemFile.path,
        '-inform',
        'PEM',
        '-RSAPublicKey_out',
        '-outform',
        'DER',
        '-out',
        output,
      ],
    );

    if (derivingResult.exitCode != ExitCode.success.code) {
      transformingKeyProgress.fail('Error transforming key');
      exit(ExitCode.software.code);
    }

    transformingKeyProgress.complete('🔐 Key derived successfully at $output');

    return ExitCode.success.code;
  }
}

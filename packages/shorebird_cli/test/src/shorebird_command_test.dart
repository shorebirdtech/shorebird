import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:test/test.dart';

import 'mocks.dart';

class _TestCommand extends ShorebirdCommand {
  @override
  String get name => 'test';

  @override
  String get description => 'A command for testing ShorebirdCommand.';
}

void main() {
  group(ShorebirdCommand, () {
    final cryptoFixturesBasePath = p.join('test', 'fixtures', 'crypto');
    final publicKeyFile = File(p.join(cryptoFixturesBasePath, 'public.pem'));
    final privateKeyFile = File(p.join(cryptoFixturesBasePath, 'private.pem'));

    late ArgParser parser;
    late _TestCommand command;

    /// A [command] whose results come from parsing [args].
    _TestCommand commandWith(List<String> args) => command
      ..testArgResults = parser.parse(args)
      ..testRunner = usageRunner();

    Matcher throwsUsage(String message) => throwsA(
      isA<UsageException>().having((e) => e.message, 'message', message),
    );

    setUp(() {
      parser = ArgParser()
        ..addOption(CommonArguments.publicKeyArg.name)
        ..addOption(CommonArguments.privateKeyArg.name)
        ..addOption(CommonArguments.publicKeyCmd.name)
        ..addOption(CommonArguments.signCmd.name);
      command = _TestCommand();
    });

    group('assertSigningArgsValid', () {
      test('succeeds when no signing arguments provided', () {
        expect(commandWith([]).assertSigningArgsValid, returnsNormally);
      });

      test('throws when both public key sources provided', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
            '--public-key-cmd=get-key-cmd',
            '--sign-cmd=sign-cmd',
          ]).assertSigningArgsValid,
          throwsUsage(
            'Pass either --public-key-path or --public-key-cmd, not both.',
          ),
        );
      });

      test('throws when both signing methods provided', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
            '--private-key-path=${privateKeyFile.path}',
            '--sign-cmd=sign-cmd',
          ]).assertSigningArgsValid,
          throwsUsage(
            'Pass either --private-key-path or --sign-cmd, not both.',
          ),
        );
      });

      test('throws when sign-cmd provided without any public key', () {
        expect(
          commandWith(['--sign-cmd=sign-cmd']).assertSigningArgsValid,
          throwsUsage(
            '--sign-cmd requires a public key: add --public-key-path=<path> '
            'or --public-key-cmd=<command>.',
          ),
        );
      });

      test('throws naming the missing key when only one file is given', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
          ]).assertSigningArgsValid,
          throwsUsage(
            '--public-key-path and --private-key-path must be passed '
            'together (missing --private-key-path).',
          ),
        );
        expect(
          commandWith([
            '--private-key-path=${privateKeyFile.path}',
          ]).assertSigningArgsValid,
          throwsUsage(
            '--public-key-path and --private-key-path must be passed '
            'together (missing --public-key-path).',
          ),
        );
      });

      test('throws naming the flag when a key file does not exist', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
            '--private-key-path=/nope/private.pem',
          ]).assertSigningArgsValid,
          throwsUsage(
            '--private-key-path: no file found at /nope/private.pem.',
          ),
        );
      });

      test('succeeds when both cmd arguments provided', () {
        expect(
          commandWith([
            '--public-key-cmd=get-key-cmd',
            '--sign-cmd=sign-cmd',
          ]).assertSigningArgsValid,
          returnsNormally,
        );
      });

      test('succeeds with public-key-path + sign-cmd (mixed)', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
            '--sign-cmd=sign-cmd',
          ]).assertSigningArgsValid,
          returnsNormally,
        );
      });

      test('succeeds when both file arguments provided with valid files', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
            '--private-key-path=${privateKeyFile.path}',
          ]).assertSigningArgsValid,
          returnsNormally,
        );
      });
    });

    group('assertPublicKeyArgsValid', () {
      test('succeeds when no public key arguments provided', () {
        expect(commandWith([]).assertPublicKeyArgsValid, returnsNormally);
      });

      test('succeeds when only public-key-path provided', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
          ]).assertPublicKeyArgsValid,
          returnsNormally,
        );
      });

      test('succeeds when only public-key-cmd provided', () {
        expect(
          commandWith([
            '--public-key-cmd=get-key-cmd',
          ]).assertPublicKeyArgsValid,
          returnsNormally,
        );
      });

      test('throws when both public-key-path and public-key-cmd provided', () {
        expect(
          commandWith([
            '--public-key-path=${publicKeyFile.path}',
            '--public-key-cmd=get-key-cmd',
          ]).assertPublicKeyArgsValid,
          throwsUsage(
            'Pass either --public-key-path or --public-key-cmd, not both.',
          ),
        );
      });

      test('throws naming the flag when the public key does not exist', () {
        expect(
          commandWith([
            '--public-key-path=/nope/public.pem',
          ]).assertPublicKeyArgsValid,
          throwsUsage('--public-key-path: no file found at /nope/public.pem.'),
        );
      });
    });
  });
}

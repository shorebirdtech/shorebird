// ignore_for_file: public_member_api_docs
import 'dart:io';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/extensions/file.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

extension OptionFinder on ArgResults {
  /// Detects flags even when passed to underlying commands via a `--`
  /// separator.
  String? findOption(
    String name, {
    required ArgParser argParser,
  }) {
    if (wasParsed(name)) {
      return this[name] as String?;
    }

    // We would ideally check for abbreviations here as well, but ArgResults
    // doesn't expose its parser (which we could use to get the list of
    // [Options] being parsed) or an abbreviations map.
    final abbr = argParser.options.values
        .firstWhereOrNull((option) => option.name == name)
        ?.abbr;

    final flagsToCheck = [
      '--$name',
      if (abbr != null) '-$abbr',
    ];

    for (var i = 0; i < rest.length; i++) {
      for (final flag in flagsToCheck) {
        if (rest[i] == flag && i + 1 < rest.length) {
          return rest[i + 1];
        }
        final flagEqualsStart = '$flag=';
        if (rest[i].startsWith(flagEqualsStart)) {
          return rest[i].substring(flagEqualsStart.length);
        }
      }
    }

    return null;
  }
}

extension CodeSign on ArgResults {
  /// Asserts that either there is no public key argument
  /// or that the path received exists.
  void assertAbsentOrValidPublicKey() {
    file(CommonArguments.publicKeyArg.name)?.assertExists();
  }

  /// Asserts that either there is no private key argument
  /// or that the path received exists.
  void assertAbsentOrValidPrivateKey() {
    file(CommonArguments.privateKeyArg.name)?.assertExists();
  }

  /// Asserts that both public and private keys are either absent or
  /// when provided, that both of them are pointing to existing files.
  void assertAbsentOrValidKeyPair() {
    final publicKeyWasParsed = wasParsed(CommonArguments.publicKeyArg.name);
    final privateKeyWasParsed = wasParsed(CommonArguments.privateKeyArg.name);

    if (publicKeyWasParsed == privateKeyWasParsed) {
      assertAbsentOrValidPublicKey();
      assertAbsentOrValidPrivateKey();
    } else {
      logger.err('Both public and private keys must be provided.');
      throw ProcessExit(ExitCode.usage.code);
    }
  }

  /// Read the public key file and encode it to base64 if any.
  String? get encodedPublicKey {
    final publicKeyFile = file(CommonArguments.publicKeyArg.name);

    return publicKeyFile != null
        ? codeSigner.base64PublicKey(publicKeyFile)
        : null;
  }
}

/// Extension on [ArgResults] to provide file related extensions.
extension FileArgs on ArgResults {
  /// Returns a [File] from the argument [name] or null if the argument was not
  /// provided.
  File? file(String name) {
    final path = this[name] as String?;
    if (path == null) {
      return null;
    }
    return File(path);
  }
}

extension ForwardedArgs on ArgResults {
  bool _isPositionalArgPlatform(String arg) =>
      ReleaseType.values.any((target) => target.cliName == arg);

  /// All parsed args with the given name. Because of multi-options, there may
  /// be multiple values for a single name, so we return a potentially empty
  /// [Iterable<String>] instead of a [String?].
  Iterable<String> _argsNamed(String name) {
    if (!wasParsed(name)) {
      return [];
    }

    final value = this[name];
    if (value is List) {
      return value.map((a) => '--$name=$a');
    } else {
      return ['--$name=$value'];
    }
  }

  /// A list of arguments parsed by Shorebird commands that will be forwarded
  /// to the underlying Flutter commands (that is, placed after `--`).
  List<String> get forwardedArgs {
    final List<String> forwarded;
    if (rest.isNotEmpty && _isPositionalArgPlatform(rest.first)) {
      forwarded = rest.skip(1).toList();
    } else {
      forwarded = rest.toList();
    }

    forwarded.addAll(
      [
        ..._argsNamed(CommonArguments.dartDefineArg.name),
        ..._argsNamed(CommonArguments.dartDefineFromFileArg.name),
        ..._argsNamed(CommonArguments.buildNameArg.name),
        ..._argsNamed(CommonArguments.buildNumberArg.name),
      ],
    );

    return forwarded;
  }
}

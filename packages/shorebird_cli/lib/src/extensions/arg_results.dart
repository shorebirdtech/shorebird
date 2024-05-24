import 'dart:convert';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/extensions/file.dart';
import 'package:shorebird_cli/src/logger.dart';

import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/io.dart';

extension OptionFinder on ArgResults {
  /// // Detects flags even when passed to underlying commands via a `--`
  /// separator.
  String? findOption(
    String name, {
    required ArgParser argParser,
  }) {
    if (wasParsed(name)) {
      return this[name] as String?;
    }

    // We would ideally check for abbrevations here as well, but ArgResults
    // doesn't expose its parser (which we could use to get the list of
    // [Options] being parsed) or an abbrevations map.
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
    file(CommonArguments.publicKeyArgName)?.assertExists();
  }

  void assertAbsentOrValidPrivateKey() {
    file(CommonArguments.privateKeyArgName)?.assertExists();
  }

  void assertAbsentOrValidKeyPair() {
    final public = wasParsed(CommonArguments.publicKeyArgName);
    final private = wasParsed(CommonArguments.privateKeyArgName);

    if (public == private) {
      assertAbsentOrValidPublicKey();
      assertAbsentOrValidPrivateKey();
    } else {
      logger.err('Both public and private keys must be provided or absent.');
      exit(ExitCode.usage.code);
    }
  }

  /// Read the public key file and encode it to base64 if any.
  String? get encodedPublicKey {
    final publicKeyFile = file(CommonArguments.publicKeyArgName);

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

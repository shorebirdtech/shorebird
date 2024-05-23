import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:shorebird_cli/src/extensions/file.dart';

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

const _publicKeyArgName = 'public-key-path';

extension CodeSign on ArgResults {
  /// Asserts that either there is no public key argument
  /// or that the path received exists.
  void assertPublicKey() {
    file(_publicKeyArgName)?.assertExists();
  }

  /// Read the public key file and encode it to base64 if any.
  String? get encodedPublicKey {
    final publicKeyFile = file(_publicKeyArgName);

    return publicKeyFile != null
        ? base64Encode(publicKeyFile.readAsBytesSync())
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

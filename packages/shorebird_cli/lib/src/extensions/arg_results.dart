import 'dart:io';

import 'package:args/args.dart';
import 'package:collection/collection.dart';

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

/// Extension on [ArgResults] to provide file validation.
extension FileValidation on ArgResults {
  /// Checks if an option is a path that points to an existing file.
  ///
  /// This method will only return false when the argument with [name] is
  /// provided and the file does not exist.
  bool wasParsedAndFileExists(String name) {
    final filePath = this[name] as String?;
    if (filePath == null) return true;
    final file = File(this[name] as String);
    return file.existsSync();
  }
}

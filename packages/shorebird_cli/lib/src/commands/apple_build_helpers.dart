import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/platform/apple/apple.dart';

/// Reads the release version (`CFBundleShortVersionString+CFBundleVersion`)
/// from the Info.plist at [plistFile], for Apple releases.
///
/// Throws a [CommandError] exiting with [ExitCode.software] if the file does
/// not exist, cannot be parsed, or has no version. When given, [hint] is the
/// error's hint, suggesting a way around it.
String readReleaseVersionFromInfoPlist(File plistFile, {String? hint}) {
  Never fail(String message) => throw CommandError(
    message: message,
    hint: hint,
    exitCode: ExitCode.software,
  );

  if (!plistFile.existsSync()) {
    fail('No Info.plist file found at ${plistFile.path}');
  }

  try {
    return Plist(file: plistFile).versionNumber;
  } on Exception catch (error) {
    fail('Failed to determine release version from ${plistFile.path}: $error');
  }
}

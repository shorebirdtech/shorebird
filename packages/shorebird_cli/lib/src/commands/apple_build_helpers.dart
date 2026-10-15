import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform/apple/apple.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

/// Logged by patchers when the release version cannot be read from the
/// build. The version is only read when the user did not pass one, so passing
/// one is always a way around a broken read.
const passReleaseVersionHint =
    'Pass --release-version=<version> (or --release-version=latest) to '
    'skip reading the version from the build.';

/// Reads the release version (`CFBundleShortVersionString+CFBundleVersion`)
/// from the Info.plist at [plistFile], for Apple releases and patches.
///
/// Logs an error and exits with [ExitCode.software] if the file does not
/// exist, cannot be parsed, or has no version. When given, [hint] is logged
/// after the error to suggest a way around it.
String readReleaseVersionFromInfoPlist(File plistFile, {String? hint}) {
  Never fail(String message) {
    logger.err(message);
    if (hint != null) logger.info(hint);
    throw ProcessExit(ExitCode.software.code);
  }

  if (!plistFile.existsSync()) {
    fail('No Info.plist file found at ${plistFile.path}');
  }

  try {
    return Plist(file: plistFile).versionNumber;
  } on Exception catch (error) {
    fail('Failed to determine release version from ${plistFile.path}: $error');
  }
}

import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/platform/apple/apple.dart';

/// Logged by patchers when the release version cannot be read from the
/// build. The version is only read when the user did not pass one, so passing
/// one is always a way around a broken read.
const passReleaseVersionHint =
    'Pass --release-version=<version> (or --release-version=latest) to '
    'skip reading the version from the build.';

/// Reads the release version (`CFBundleShortVersionString+CFBundleVersion`)
/// from the Info.plist at [plistFile], for Apple releases and patches.
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

/// Refuses `--no-codesign` for a macOS release or patch.
///
/// `flutter build macos` has no `--no-codesign` flag: the app is signed by
/// the macOS Xcode project's own signing settings, so the build would stop
/// with "Could not find an option named --no-codesign".
void assertMacosCodesignNotDisabled(ArgResults argResults) {
  if (argResults.wasParsed('codesign') && argResults['codesign'] != true) {
    throw CommandError(
      message: '--no-codesign is not supported for macOS.',
      hint:
          'Remove --no-codesign. A macOS app is signed by the signing '
          "settings in your Xcode project's Runner target.",
    );
  }
}

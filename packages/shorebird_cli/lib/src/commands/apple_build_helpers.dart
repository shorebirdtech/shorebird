import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform/apple/apple.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

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

/// Apple-specific arguments shared by `shorebird release` and
/// `shorebird patch`.
extension AppleBuildArgs on ArgResults {
  /// Whether to codesign the build (`--codesign`, on by default).
  bool get codesign => this['codesign'] == true;

  /// Validates the `--export-options-plist` file, if one was passed.
  ///
  /// Logs an error and exits with [ExitCode.usage] if the plist would make
  /// Xcode rewrite the build number. See [assertValidExportOptionsPlist].
  void assertValidExportOptionsPlistArg() {
    final exportOptionsPlistFile = file(
      CommonArguments.exportOptionsPlistArg.name,
    );
    if (exportOptionsPlistFile == null) return;
    try {
      assertValidExportOptionsPlist(exportOptionsPlistFile);
    } on InvalidExportOptionsPlistException catch (error) {
      logger.err(error.message);
      throw ProcessExit(ExitCode.usage.code);
    }
  }
}

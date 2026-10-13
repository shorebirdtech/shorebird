import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

/// Requires `--release-version` for add-to-app releases (aar, ios-framework).
///
/// Presence-only: empty values and `latest` still pass. Opposite of
/// `Releaser.assertReleaseVersionFlagNotProvided`.
void assertReleaseVersionProvided({
  required ArgResults argResults,
  required String hostAppLabel,
  required String exampleCommand,
}) {
  if (argResults.wasParsed('release-version')) {
    return;
  }

  logger.err('''
Missing required argument: --release-version.

Pass the version of the $hostAppLabel app that embeds this module
(e.g. $releaseVersionExample).

Example:
  ${lightCyan.wrap(exampleCommand)}
''');
  throw ProcessExit(ExitCode.usage.code);
}

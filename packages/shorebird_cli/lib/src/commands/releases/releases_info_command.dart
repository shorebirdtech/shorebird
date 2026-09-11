import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template releases_info_command}
/// `shorebird releases info`
/// Show details for a specific release.
/// {@endtemplate}
class ReleasesInfoCommand extends ShorebirdCommand {
  /// {@macro releases_info_command}
  ReleasesInfoCommand() {
    argParser
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        help: CommonArguments.releaseVersionArg.description,
        mandatory: true,
      )
      ..addOption(
        CommonArguments.appIdArg.name,
        help: CommonArguments.appIdArg.description,
      )
      ..addOption(
        CommonArguments.flavorArg.name,
        help: 'The product flavor to query releases for (e.g. "prod").',
      );
  }

  @override
  String get name => 'info';

  @override
  String get description =>
      'Show details for a specific release.\n\n'
      'Example output:\n'
      '  ID:         42\n'
      '  Version:    1.0.0+1\n'
      '  Flutter:    3.27.0\n'
      '  Revision:   abc123def\n'
      '  Created:    2026-01-15\n'
      '  Updated:    2026-01-16\n'
      '  Notes:      Optional release notes.\n'
      '  Platforms:\n'
      '    android:  active\n'
      '    ios:      draft\n'
      '    macos:    active\n'
      '    windows:  active\n\n'
      '${ShorebirdCommand.jsonHint('shorebird releases info --release-version 1.0.0+1 --app-id <id> --json')}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final releaseVersion =
        results[CommonArguments.releaseVersionArg.name] as String;

    final Release release;
    try {
      release = await codePushClientWrapper.getRelease(
        appId: appId,
        releaseVersion: releaseVersion,
      );
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.fetchFailed,
          message: 'Failed to fetch release "$releaseVersion".',
        );
        return e.exitCode;
      }
      rethrow;
    }

    if (isJsonMode) {
      emitJsonSuccess({'release': release.toJson()});
      return ExitCode.success.code;
    }

    logger.info('ID:         ${release.id}');
    logger.info('Version:    ${release.version}');
    if (release.flutterVersion != null) {
      logger.info('Flutter:    ${release.flutterVersion}');
    }
    logger.info('Revision:   ${release.flutterRevision}');
    logger
      ..info(
        'Created:    '
        '${release.createdAt.toIso8601String().split('T').first}',
      )
      ..info(
        'Updated:    '
        '${release.updatedAt.toIso8601String().split('T').first}',
      );
    if (release.notes != null) {
      logger.info('Notes:      ${release.notes}');
    }
    logger.info('Platforms:');
    for (final entry in release.platformStatuses.entries) {
      final label = '${entry.key.value}:'.padRight(10);
      logger.info('  $label${entry.value.value}');
    }

    return ExitCode.success.code;
  }
}

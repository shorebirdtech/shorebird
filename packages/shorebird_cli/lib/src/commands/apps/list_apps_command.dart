import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template list_apps_command}
///
/// `shorebird apps list`
/// List all apps using Shorebird.
/// {@endtemplate}
class ListAppsCommand extends ShorebirdCommand with ShorebirdConfigMixin {
  /// {@macro list_apps_command}
  ListAppsCommand({
    required super.logger,
    super.buildCodePushClient,
    super.auth,
  });

  @override
  String get description => 'List all apps using Shorebird.';

  @override
  String get name => 'list';

  @override
  List<String> get aliases => ['ls'];

  @override
  Future<int>? run() async {
    final session = auth.currentSession;
    if (session == null) {
      logger.err('You must be logged in.');
      return ExitCode.noUser.code;
    }

    final client = buildCodePushClient(
      apiKey: session.apiKey,
      hostedUri: hostedUri,
    );

    late final List<App> apps;
    try {
      apps = await client.getApps();
    } catch (error) {
      logger.err('Unable to get apps: $error');
      return ExitCode.software.code;
    }

    if (apps.isEmpty) {
      logger.info('(empty)');
      return ExitCode.success.code;
    }

    for (final app in apps) {
      logger.info(app.prettyPrint());
    }

    return ExitCode.success.code;
  }
}

extension on App {
  String prettyPrint() {
    final latestReleasePart =
        latestReleaseVersion != null ? 'v$latestReleaseVersion' : '(empty)';
    final latestPatchPart =
        latestPatchNumber != null ? '(patch #$latestPatchNumber)' : '';
    return '$appId: $latestReleasePart $latestPatchPart';
  }
}

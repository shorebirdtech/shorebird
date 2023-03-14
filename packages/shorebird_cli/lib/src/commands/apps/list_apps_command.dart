import 'dart:async';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template list_apps_command}
///
/// `shorebird apps list`
/// List all apps using Shorebird.
/// {@endtemplate}
class ListAppsCommand extends ShorebirdCommand {
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

    final client = buildCodePushClient(apiKey: session.apiKey);

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
    final latestRelease = releases.lastOrNull;
    final latestPatch = latestRelease?.patches.lastOrNull;
    final latestReleasePart =
        latestRelease != null ? 'v${latestRelease.version}' : '(empty)';
    final latestPatchPart =
        latestPatch != null ? '(patch #${latestPatch.number})' : '';

    return '$productId: $latestReleasePart $latestPatchPart';
  }
}

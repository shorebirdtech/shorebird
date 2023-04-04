import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template init_command}
///
/// `shorebird init`
/// Initialize Shorebird.
/// {@endtemplate}
class InitCommand extends ShorebirdCommand
    with ShorebirdConfigMixin, ShorebirdCreateAppMixin {
  /// {@macro init_command}
  InitCommand({required super.logger, super.auth, super.buildCodePushClient});

  @override
  String get description => 'Initialize Shorebird.';

  @override
  String get name => 'init';

  @override
  Future<int> run() async {
    if (auth.credentials == null) {
      logger.err('You must be logged in.');
      return ExitCode.noUser.code;
    }

    final progress = logger.progress('Initializing Shorebird');
    try {
      if (!hasPubspecYaml) {
        progress.fail('''
Could not find a "pubspec.yaml".
Please make sure you are running "shorebird init" from the root of your Flutter project.
''');
        return ExitCode.noInput.code;
      }
    } catch (error) {
      progress.fail('Error parsing "pubspec.yaml": $error');
      return ExitCode.software.code;
    }

    final ShorebirdYaml? shorebirdYaml;
    try {
      shorebirdYaml = getShorebirdYaml();
    } catch (_) {
      progress.fail('Error parsing "shorebird.yaml".');
      return ExitCode.software.code;
    }

    String? appId;

    if (shorebirdYaml != null) {
      final codePushClient = buildCodePushClient(
        httpClient: auth.client,
        hostedUri: hostedUri,
      );

      final List<App> apps;
      final fetchAppsProgress = logger.progress('Fetching apps');
      try {
        apps = (await codePushClient.getApps())
            .map((a) => App(id: a.appId, displayName: a.displayName))
            .toList();
        fetchAppsProgress.complete();
      } catch (error) {
        fetchAppsProgress.fail('$error');
        return ExitCode.software.code;
      }

      final app = apps.firstWhereOrNull((a) => a.id == shorebirdYaml!.appId);
      appId = app?.id;
    }

    if (appId == null) {
      try {
        final app = await createApp();
        appId = app.id;
      } catch (error) {
        progress.fail('$error');
        return ExitCode.software.code;
      }
    }

    if (shorebirdYaml != null) {
      progress.update('Updating "shorebird.yaml"');
    } else {
      progress.update('Creating "shorebird.yaml"');
    }

    addShorebirdYamlToProject(appId);

    progress.update('Adding "shorebird.yaml" to "pubspec.yaml" assets');

    if (pubspecContainsShorebirdYaml) {
      progress.update('"shorebird.yaml" already in "pubspec.yaml" assets.');
    } else {
      addShorebirdYamlToPubspecAssets();
    }

    progress.complete('Initialized Shorebird');

    logger.info(
      '''

${lightGreen.wrap('🐦 Shorebird initialized successfully!')}

✅ A shorebird app has been created.
✅ A "shorebird.yaml" has been created.
✅ The "pubspec.yaml" has been updated to include "shorebird.yaml" as an asset.

Reference the following commands to get started:

🚙 To run your project use: "${lightCyan.wrap('shorebird run')}".
📦 To build your project use: "${lightCyan.wrap('shorebird build')}".
🚀 To push an update use: "${lightCyan.wrap('shorebird patch')}".

For more information about Shorebird, visit ${link(uri: Uri.parse('https://shorebird.dev'))}''',
    );
    return ExitCode.success.code;
  }
}

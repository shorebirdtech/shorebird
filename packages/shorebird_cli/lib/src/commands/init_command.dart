import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';

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
    final session = auth.currentSession;
    if (session == null) {
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

    late final bool shorebirdYamlExists;
    try {
      shorebirdYamlExists = hasShorebirdYaml;
    } catch (_) {
      progress.fail('Error parsing "shorebird.yaml".');
      return ExitCode.software.code;
    }

    late final String appId;
    if (!shorebirdYamlExists) {
      try {
        final app = await createApp();
        appId = app.id;
      } catch (error) {
        progress.fail('$error');
        return ExitCode.software.code;
      }
    } else {
      appId = getShorebirdYaml()!.appId;
    }

    if (shorebirdYamlExists) {
      progress.update('"shorebird.yaml" already exists.');
    } else {
      progress.update('Creating "shorebird.yaml"');
      addShorebirdYamlToProject(appId);
      progress.update('Generated a "shorebird.yaml".');
    }

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

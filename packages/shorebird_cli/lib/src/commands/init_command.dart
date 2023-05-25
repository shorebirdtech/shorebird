import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth_logger_mixin.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';
import 'package:shorebird_cli/src/shorebird_flavor_mixin.dart';
import 'package:shorebird_cli/src/shorebird_java_mixin.dart';

/// {@template init_command}
///
/// `shorebird init`
/// Initialize Shorebird.
/// {@endtemplate}
class InitCommand extends ShorebirdCommand
    with
        AuthLoggerMixin,
        ShorebirdConfigMixin,
        ShorebirdCreateAppMixin,
        ShorebirdJavaMixin,
        ShorebirdFlavorMixin {
  /// {@macro init_command}
  InitCommand({required super.logger, super.auth, super.buildCodePushClient}) {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Initialize the app even if a "shorebird.yaml" already exists.',
      negatable: false,
    );
  }

  @override
  String get description => 'Initialize Shorebird.';

  @override
  String get name => 'init';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      printNeedsAuthInstructions();
      return ExitCode.noUser.code;
    }

    try {
      if (!hasPubspecYaml) {
        logger.err('''
Could not find a "pubspec.yaml".
Please make sure you are running "shorebird init" from the root of your Flutter project.
''');
        return ExitCode.noInput.code;
      }
    } catch (error) {
      logger.err('Error parsing "pubspec.yaml": $error');
      return ExitCode.software.code;
    }

    final force = results['force'] == true;
    if (force && hasShorebirdYaml) {
      getShorebirdYamlFile().deleteSync();
    }

    if (hasShorebirdYaml) {
      logger.err('''
A "shorebird.yaml" already exists.
If you want to reinitialize Shorebird, please run "shorebird init --force".''');
      return ExitCode.software.code;
    }

    var productFlavors = <String>{};
    final detectFlavorsProgress = logger.progress('Detecting product flavors');
    try {
      productFlavors = await extractProductFlavors(Directory.current.path);
    } catch (error) {
      logger.detail('Unable to extract product flavors: $error');
    } finally {
      detectFlavorsProgress.complete();
    }

    final String appId;
    Map<String, String>? flavors;
    try {
      final displayName = logger.prompt(
        '${lightGreen.wrap('?')} How should we refer to this app?',
        defaultValue: getPubspecYaml()?.name,
      );

      if (productFlavors.isNotEmpty) {
        final values = <String, String>{};
        for (final flavor in productFlavors) {
          values[flavor] =
              (await createApp(appName: '$displayName ($flavor)')).id;
        }
        flavors = values;
        appId = flavors.values.first;
      } else {
        appId = (await createApp(appName: displayName)).id;
      }
    } catch (error) {
      logger.err('$error');
      return ExitCode.software.code;
    }

    addShorebirdYamlToProject(appId, flavors: flavors);

    if (!pubspecContainsShorebirdYaml) addShorebirdYamlToPubspecAssets();

    logger.info(
      '''

${lightGreen.wrap('🐦 Shorebird initialized successfully!')}

✅ A shorebird app has been created.
✅ A "shorebird.yaml" has been created.
✅ The "pubspec.yaml" has been updated to include "shorebird.yaml" as an asset.

Reference the following commands to get started:

🚙 To run your project use: "${lightCyan.wrap('shorebird run')}".
📦 To create a new release use: "${lightCyan.wrap('shorebird release')}".
🚀 To push an update use: "${lightCyan.wrap('shorebird patch')}".

For more information about Shorebird, visit ${link(uri: Uri.parse('https://shorebird.dev'))}''',
    );
    return ExitCode.success.code;
  }
}

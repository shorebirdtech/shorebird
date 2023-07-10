import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_flavor_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';

/// {@template init_command}
///
/// `shorebird init`
/// Initialize Shorebird.
/// {@endtemplate}
class InitCommand extends ShorebirdCommand
    with
        ShorebirdConfigMixin,
        ShorebirdValidationMixin,
        ShorebirdCreateAppMixin,
        ShorebirdFlavorMixin {
  /// {@macro init_command}
  InitCommand({super.buildCodePushClient}) {
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
    try {
      await validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
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
      ShorebirdEnvironment.getShorebirdYamlFile().deleteSync();
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
      detectFlavorsProgress.complete();
    } catch (error) {
      detectFlavorsProgress.fail();
      logger.err('Unable to extract product flavors.\n$error');
      return ExitCode.software.code;
    }

    final String appId;
    Map<String, String>? flavors;
    try {
      final displayName = logger.prompt(
        '${lightGreen.wrap('?')} How should we refer to this app?',
        defaultValue: ShorebirdEnvironment.getPubspecYaml()?.name,
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

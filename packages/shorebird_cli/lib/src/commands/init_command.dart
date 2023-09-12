import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/gradlew.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/xcodebuild.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// {@template init_command}
///
/// `shorebird init`
/// Initialize Shorebird.
/// {@endtemplate}
class InitCommand extends ShorebirdCommand {
  /// {@macro init_command}
  InitCommand() {
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
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    try {
      if (!shorebirdEnv.hasPubspecYaml) {
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

    Set<String>? androidFlavors;
    Set<String>? iosFlavors;
    var productFlavors = <String>{};
    final detectFlavorsProgress = logger.progress('Detecting product flavors');
    try {
      final flavors = await Future.wait([
        _maybeGetAndroidFlavors(Directory.current.path),
        _maybeGetiOSFlavors(Directory.current.path),
      ]);
      androidFlavors = flavors[0];
      iosFlavors = flavors[1];
      productFlavors = <String>{
        if (androidFlavors != null) ...androidFlavors,
        if (iosFlavors != null) ...iosFlavors,
      };
      detectFlavorsProgress.complete();
    } catch (error) {
      detectFlavorsProgress.fail();
      logger.err('Unable to extract product flavors.\n$error');
      return ExitCode.software.code;
    }

    final shorebirdYaml = shorebirdEnv.getShorebirdYaml();
    final existingFlavors = shorebirdYaml?.flavors;
    Set<String> newFlavors;
    if (existingFlavors != null) {
      final existingFlavorNames = existingFlavors.keys.toSet();
      newFlavors = productFlavors.difference(existingFlavorNames);
    } else {
      newFlavors = {};
    }

    // New flavors not being empty means that we have existing flavors, which
    // means that there is already an existing app.
    // If the --force flag is present, we will completely reinit the app and
    // don't care about which flavors are new.
    if (!force && newFlavors.isNotEmpty) {
      logger.info('New flavors detected: ${newFlavors.join(', ')}');
      final updateShorebirdYamlProgress =
          logger.progress('Adding flavors to shorebird.yaml');

      final AppMetadata existingApp;
      try {
        existingApp =
            await codePushClientWrapper.getApp(appId: shorebirdYaml!.appId);
      } catch (e) {
        updateShorebirdYamlProgress.fail('Failed to get existing app info: $e');
        return ExitCode.software.code;
      }

      final deflavoredAppName =
          existingApp.displayName.replaceAll(RegExp(r'\(.*\)'), '').trim();
      final flavorsToAppIds = shorebirdYaml.flavors!;
      for (final flavor in newFlavors) {
        final app = await codePushClientWrapper.createApp(
          appName: '$deflavoredAppName ($flavor)',
        );
        flavorsToAppIds[flavor] = app.id;
      }
      _addShorebirdYamlToProject(
        shorebirdYaml.appId,
        flavors: flavorsToAppIds,
      );
      updateShorebirdYamlProgress.complete('Flavors added to shorebird.yaml');
      return ExitCode.success.code;
    }

    if (!force && shorebirdEnv.hasShorebirdYaml) {
      logger
        ..err('A "shorebird.yaml" file already exists and seems up-to-date.')
        ..info(
          '''If you want to reinitialize Shorebird, please run ${lightCyan.wrap('shorebird init --force')}.''',
        );
      return ExitCode.software.code;
    }

    final String appId;
    Map<String, String>? flavors;
    try {
      final displayName = logger.prompt(
        '${lightGreen.wrap('?')} How should we refer to this app?',
        defaultValue: shorebirdEnv.getPubspecYaml()?.name,
      );
      final hasNoFlavors = productFlavors.isEmpty;
      final hasSomeFlavors = productFlavors.isNotEmpty &&
          ((androidFlavors?.isEmpty ?? false) ||
              (iosFlavors?.isEmpty ?? false));

      if (hasNoFlavors) {
        // No platforms have any flavors so we just create a single app
        // and assign it as the default.
        final app = await codePushClientWrapper.createApp(appName: displayName);
        appId = app.id;
      } else if (hasSomeFlavors) {
        // Some platforms have flavors and some do not so we create an app
        // for the default (no flavor) and then create an app per flavor.
        final app = await codePushClientWrapper.createApp(appName: displayName);
        appId = app.id;
        final values = <String, String>{};
        for (final flavor in productFlavors) {
          final app = await codePushClientWrapper.createApp(
            appName: '$displayName ($flavor)',
          );
          values[flavor] = app.id;
        }
        flavors = values;
      } else {
        // All platforms have flavors so we create an app per flavor
        // and assign the default to the first flavor.
        final values = <String, String>{};
        for (final flavor in productFlavors) {
          final app = await codePushClientWrapper.createApp(
            appName: '$displayName ($flavor)',
          );
          values[flavor] = app.id;
        }
        flavors = values;
        appId = flavors.values.first;
      }
    } catch (error) {
      logger.err('$error');
      return ExitCode.software.code;
    }

    _addShorebirdYamlToProject(appId, flavors: flavors);

    if (!shorebirdEnv.pubspecContainsShorebirdYaml) {
      _addShorebirdYamlToPubspecAssets();
    }

    await doctor.runValidators(doctor.allValidators, applyFixes: true);

    logger.info(
      '''

${lightGreen.wrap('🐦 Shorebird initialized successfully!')}

✅ A shorebird app has been created.
✅ A "shorebird.yaml" has been created.
✅ The "pubspec.yaml" has been updated to include "shorebird.yaml" as an asset.

Reference the following commands to get started:

📦 To create a new release use: "${lightCyan.wrap('shorebird release')}".
🚀 To push an update use: "${lightCyan.wrap('shorebird patch')}".
👀 To preview a release use: "${lightCyan.wrap('shorebird preview')}".

For more information about Shorebird, visit ${link(uri: Uri.parse('https://shorebird.dev'))}''',
    );
    return ExitCode.success.code;
  }

  Future<Set<String>?> _maybeGetAndroidFlavors(String projectPath) async {
    try {
      return await gradlew.productFlavors(projectPath);
    } on MissingAndroidProjectException {
      return null;
    }
  }

  Future<Set<String>?> _maybeGetiOSFlavors(String projectPath) async {
    if (platform.isMacOS) {
      try {
        final info = await xcodeBuild.list(projectPath);
        return info.schemes.whereNot((element) => element == 'Runner').toSet();
      } on MissingIOSProjectException {
        return null;
      }
    } else {
      // When running on a non-macOS platform, we can't use `xcodebuild` to
      // detect flavors so we fallback to looking for schemes in xcschemes.
      // Note: this appears to be identical to the behavior of `xcodebuild`.
      final iosDir = Directory(p.join(projectPath, 'ios'));
      if (!iosDir.existsSync()) return null;
      final xcschemesDir = Directory(
        p.join(
          iosDir.path,
          'Runner.xcodeproj',
          'xcshareddata',
          'xcschemes',
        ),
      );
      if (!xcschemesDir.existsSync()) {
        throw Exception('Unable to detect iOS schemes in $xcschemesDir');
      }
      return xcschemesDir
          .listSync()
          .whereType<File>()
          .where((e) => p.basename(e.path).endsWith('.xcscheme'))
          .where((e) => p.basenameWithoutExtension(e.path) != 'Runner')
          .map((file) => p.basename(file.path).split('.xcscheme').first)
          .sorted()
          .toSet();
    }
  }

  ShorebirdYaml _addShorebirdYamlToProject(
    String appId, {
    Map<String, String>? flavors,
  }) {
    const content = '''
# This file is used to configure the Shorebird updater used by your app.
# Learn more at https://docs.shorebird.dev
# This file should be checked into version control.

# This is the unique identifier assigned to your app.
# Your app_id is not a secret and is just used to identify your app
# when requesting patches from Shorebird's servers.
app_id:

# auto_update controls if Shorebird should automatically update in the background on launch.
# If auto_update: false, you will need to use package:shorebird_code_push to trigger updates.
# https://pub.dev/packages/shorebird_code_push
# Uncomment the following line to disable automatic updates.
# auto_update: false
''';

    final editor = YamlEditor(content)..update(['app_id'], appId);

    if (flavors != null) editor.update(['flavors'], flavors);

    shorebirdEnv.getShorebirdYamlFile().writeAsStringSync(editor.toString());

    return ShorebirdYaml(appId: appId);
  }

  void _addShorebirdYamlToPubspecAssets() {
    final pubspecFile = shorebirdEnv.getPubspecYamlFile();
    final pubspecContents = pubspecFile.readAsStringSync();
    final yaml = loadYaml(pubspecContents, sourceUrl: pubspecFile.uri) as Map;
    final editor = YamlEditor(pubspecContents);

    if (!yaml.containsKey('flutter')) {
      editor.update(
        ['flutter'],
        {
          'assets': ['shorebird.yaml'],
        },
      );
    } else {
      if (!(yaml['flutter'] as Map).containsKey('assets')) {
        editor.update(['flutter', 'assets'], ['shorebird.yaml']);
      } else {
        final assets = (yaml['flutter'] as Map)['assets'] as List;
        if (!assets.contains('shorebird.yaml')) {
          editor.update(['flutter', 'assets'], [...assets, 'shorebird.yaml']);
        }
      }
    }

    if (editor.edits.isEmpty) return;

    pubspecFile.writeAsStringSync(editor.toString());
  }
}

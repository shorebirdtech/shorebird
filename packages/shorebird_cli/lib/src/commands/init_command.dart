import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/gradlew.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';
import 'package:shorebird_cli/src/xcodebuild.dart';

/// {@template init_command}
///
/// `shorebird init`
/// Initialize Shorebird.
/// {@endtemplate}
class InitCommand extends ShorebirdCommand
    with
        ShorebirdConfigMixin,
        ShorebirdValidationMixin,
        ShorebirdCreateAppMixin {
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

    final String appId;
    Map<String, String>? flavors;
    try {
      final displayName = logger.prompt(
        '${lightGreen.wrap('?')} How should we refer to this app?',
        defaultValue: ShorebirdEnvironment.getPubspecYaml()?.name,
      );
      final hasNoFlavors = productFlavors.isEmpty;
      final hasSomeFlavors = productFlavors.isNotEmpty &&
          ((androidFlavors?.isEmpty ?? false) ||
              (iosFlavors?.isEmpty ?? false));

      if (hasNoFlavors) {
        // No platforms have any flavors so we just create a single app
        // and assign it as the default.
        appId = (await createApp(appName: displayName)).id;
      } else if (hasSomeFlavors) {
        // Some platforms have flavors and some do not so we create an app
        // for the default (no flavor) and then create an app per flavor.
        appId = (await createApp(appName: displayName)).id;
        final values = <String, String>{};
        for (final flavor in productFlavors) {
          values[flavor] =
              (await createApp(appName: '$displayName ($flavor)')).id;
        }
        flavors = values;
      } else {
        // All platforms have flavors so we create an app per flavor
        // and assign the default to the first flavor.
        final values = <String, String>{};
        for (final flavor in productFlavors) {
          values[flavor] =
              (await createApp(appName: '$displayName ($flavor)')).id;
        }
        flavors = values;
        appId = flavors.values.first;
      }
    } catch (error) {
      logger.err('$error');
      return ExitCode.software.code;
    }

    addShorebirdYamlToProject(appId, flavors: flavors);

    if (!pubspecContainsShorebirdYaml) addShorebirdYamlToPubspecAssets();

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
      final xcschemesDir = Directory(
        p.join(
          projectPath,
          'ios',
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
          .toSet();
    }
  }
}

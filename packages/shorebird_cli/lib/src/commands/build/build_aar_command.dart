import 'dart:async';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth_logger_mixin.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';

/// {@template build_aar_command}
///
/// `shorebird build aar`
/// Build an Android aar file from your app.
/// {@endtemplate}
class BuildAarCommand extends ShorebirdCommand
    with
        AuthLoggerMixin,
        ShorebirdValidationMixin,
        ShorebirdConfigMixin,
        ShorebirdBuildMixin {
  BuildAarCommand({
    required super.logger,
    super.auth,
  }) {
    // We would have a "target" option here, similar to what [BuildApkCommand]
    // and [BuildAabCommand] have, but target cannot currently be configured in
    // `flutter build aar` and is always assumed to be lib/main.dart.
    argParser
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      )
      // `flutter build aar` defaults to a build number of 1.0, so we do the
      // same.
      ..addOption(
        'build-number',
        help: 'The build number of the aar',
        defaultsTo: '1.0',
      );
  }

  @override
  String get name => 'aar';

  @override
  String get description => 'Build an Android AAR file from your module.';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      printNeedsAuthInstructions();
      return ExitCode.noUser.code;
    }

    final pubspec = getPubspecYaml();
    if (pubspec == null) {
      logger.err('No pubspec.yaml file found.');
      return ExitCode.config.code;
    }

    final module = pubspec.flutter?['module'] as Map?;
    final androidPackageName = module?['androidPackage'] as String?;
    if (androidPackageName == null) {
      logger.err('Could not find androidPackage in pubspec.yaml.');
      return ExitCode.config.code;
    }

    final flavor = results['flavor'] as String?;
    final buildNumber = results['build-number'] as String;
    final buildProgress = logger.progress('Building aar');
    try {
      await buildAar(buildNumber: buildNumber, flavor: flavor);
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    buildProgress.complete();

    final aarPath = p.joinAll([
      'build',
      'host',
      'outputs',
      'repo',
      ...androidPackageName.split('.'),
      'flutter_release',
      buildNumber,
      'flutter_release-$buildNumber.aar',
    ]);

    logger.info('''
📦 Generated an aar at:
${lightCyan.wrap(aarPath)}''');

    return ExitCode.success.code;
  }
}

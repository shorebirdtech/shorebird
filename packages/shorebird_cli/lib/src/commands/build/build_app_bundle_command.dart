import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template build_app_bundle_command}
///
/// `shorebird build appbundle`
/// Build an Android App Bundle file from your app.
/// {@endtemplate}
class BuildAppBundleCommand extends ShorebirdCommand
    with ShorebirdConfigMixin, ShorebirdBuildMixin {
  /// {@macro build_app_bundle_command}
  BuildAppBundleCommand() {
    argParser
      ..addOption(
        'target',
        abbr: 't',
        help: 'The main entrypoint file of the application.',
      )
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      );
  }

  @override
  String get description => 'Build an Android App Bundle file from your app.';

  @override
  String get name => 'appbundle';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.androidCommandValidators,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final flavor = results['flavor'] as String?;
    final target = results['target'] as String?;
    final buildProgress = logger.progress('Building appbundle');
    try {
      await buildAppBundle(flavor: flavor, target: target);
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    final bundleDirPath = p.join('build', 'app', 'outputs', 'bundle');
    final bundlePath = flavor != null
        ? p.join(bundleDirPath, '${flavor}Release', 'app-$flavor-release.aab')
        : p.join(bundleDirPath, 'release', 'app-release.aab');

    buildProgress.complete();
    logger.info('''
📦 Generated an app bundle at:
${lightCyan.wrap(bundlePath)}''');

    return ExitCode.success.code;
  }
}

import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth_logger_mixin.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';

/// {@template build_app_bundle_command}
///
/// `shorebird build appbundle`
/// Build an Android App Bundle file from your app.
/// {@endtemplate}
class BuildAppBundleCommand extends ShorebirdCommand
    with
        AuthLoggerMixin,
        ShorebirdValidationMixin,
        ShorebirdConfigMixin,
        ShorebirdBuildMixin {
  /// {@macro build_app_bundle_command}
  BuildAppBundleCommand({
    required super.logger,
    super.auth,
    super.validators,
  }) {
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
    if (!auth.isAuthenticated) {
      printNeedsAuthInstructions();
      return ExitCode.noUser.code;
    }

    final validationIssues = await runValidators();
    if (validationIssuesContainsError(validationIssues)) {
      logValidationFailure(issues: validationIssues);
      return ExitCode.config.code;
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

    final bundlePath = flavor != null
        ? './build/app/outputs/bundle/${flavor}Release/app-$flavor-release.aab'
        : './build/app/outputs/bundle/release/app-release.aab';

    buildProgress.complete();
    logger.info('''
📦 Generated an app bundle at:
${lightCyan.wrap(bundlePath)}''');

    return ExitCode.success.code;
  }
}

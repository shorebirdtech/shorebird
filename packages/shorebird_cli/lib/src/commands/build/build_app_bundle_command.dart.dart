import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/flutter_validation_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';

/// {@template build_app_bundle_command}
///
/// `shorebird build appbundle`
/// Build an Android App Bundle file from your app.
/// {@endtemplate}
class BuildAppBundleCommand extends ShorebirdCommand
    with ShorebirdValidationMixin, ShorebirdConfigMixin, ShorebirdBuildMixin {
  /// {@macro build_app_bundle_command}
  BuildAppBundleCommand({
    required super.logger,
    super.auth,
    super.validators,
  });

  @override
  String get description => 'Build an Android App Bundle file from your app.';

  @override
  String get name => 'appbundle';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      logger
        ..err('You must be logged in to build.')
        ..err("Run 'shorebird login' to log in and try again.");
      return ExitCode.noUser.code;
    }

    await logValidationIssues();

    final buildProgress = logger.progress('Building appbundle');
    try {
      await buildAppBundle();
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    buildProgress.complete();
    logger.info('''
📦 Generated an app bundle at:
${lightCyan.wrap("./build/app/outputs/bundle/release/app-release.aab")}''');

    return ExitCode.success.code;
  }
}

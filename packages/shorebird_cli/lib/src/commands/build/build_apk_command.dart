import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/flutter_validation_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';

/// {@template build_apk_command}
///
/// `shorebird build apk`
/// Build an Android APK file from your app.
/// {@endtemplate}
class BuildApkCommand extends ShorebirdCommand
    with ShorebirdValidationMixin, ShorebirdConfigMixin, ShorebirdBuildMixin {
  /// {@macro build_apk_command}
  BuildApkCommand({
    required super.logger,
    super.auth,
    super.runProcess,
    super.validators,
  });

  @override
  String get description => 'Build an Android APK file from your app.';

  @override
  String get name => 'apk';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      logger
        ..err('You must be logged in to build.')
        ..err("Run 'shorebird login' to log in and try again.");
      return ExitCode.noUser.code;
    }

    await logValidationIssues();

    final buildProgress = logger.progress('Building apk');
    try {
      await buildApk();
      buildProgress.complete();
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    return ExitCode.success.code;
  }
}

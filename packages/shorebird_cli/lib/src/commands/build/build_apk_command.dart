import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth_logger_mixin.dart';
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
    with
        AuthLoggerMixin,
        ShorebirdValidationMixin,
        ShorebirdConfigMixin,
        ShorebirdBuildMixin {
  /// {@macro build_apk_command}
  BuildApkCommand({
    required super.logger,
    super.auth,
    super.validators,
  });

  @override
  String get description => 'Build an Android APK file from your app.';

  @override
  String get name => 'apk';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      printNeedsAuthInstructions();
      return ExitCode.noUser.code;
    }

    await logValidationIssues();

    final buildProgress = logger.progress('Building apk');
    try {
      await buildApk();
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    buildProgress.complete();

    logger.info('''
📦 Generated an apk at:
${lightCyan.wrap("./build/app/outputs/apk/release/app-release.apk")}''');

    return ExitCode.success.code;
  }
}

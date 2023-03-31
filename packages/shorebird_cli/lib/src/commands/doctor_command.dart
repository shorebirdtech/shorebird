import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_version_mixin.dart';
import 'package:shorebird_cli/src/version.dart';

/// {@template doctor_command}
///
/// `shorebird doctor`
/// A command that checks for potential issues with the current shorebird
/// environment.
/// {@endtemplate}
class DoctorCommand extends ShorebirdCommand with ShorebirdVersionMixin {
  /// {@macro doctor_command}
  DoctorCommand({required super.logger, super.runProcess});

  @override
  String get name => 'doctor';

  @override
  String get description => 'Show information about the installed tooling.';

  @override
  Future<int> run() async {
    var numIssues = 0;
    final workingDirectory = p.dirname(Platform.script.toFilePath());
    logger.info('''
Doctor summary

Shorebird v$packageVersion
''');

    final isShorebirdUpToDate = await isShorebirdVersionCurrent(
      workingDirectory: workingDirectory,
    );

    if (!isShorebirdUpToDate) {
      numIssues += 1;
      logger.info('''
A new version of shorebird is available!
Run `shorebird upgrade` to upgrade.
''');
    }

    if (numIssues == 0) {
      logger.info('No issues detected!');
    } else {
      logger.info('$numIssues issue${numIssues == 1 ? '' : 's'} detected.');
    }

    return ExitCode.success.code;
  }
}

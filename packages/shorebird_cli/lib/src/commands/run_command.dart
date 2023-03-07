import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_engine_mixin.dart';

typedef StartProcess = Future<Process> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

/// {@template run_command}
///
/// `shorebird run`
/// Run the Flutter application.
/// {@endtemplate}
class RunCommand extends ShorebirdCommand with ShorebirdEngineMixin {
  /// {@macro run_command}
  RunCommand({
    super.auth,
    super.buildCodePushClient,
    super.logger,
    super.startProcess,
  });

  @override
  String get description => 'Run the Flutter application.';

  @override
  String get name => 'run';

  @override
  Future<int> run() async {
    if (auth.currentSession == null) {
      logger
        ..err('You must be logged in to run.')
        ..err("Run 'shorebird login' to log in and try again.");
      return ExitCode.noUser.code;
    }

    try {
      await ensureEngineExists();
    } catch (error) {
      logger.err(error.toString());
      return ExitCode.software.code;
    }

    logger.info('Running app...');
    final process = await startProcess(
      'flutter',
      [
        'run',
        // Eventually we should support running in both debug and release mode.
        '--release',
        '--local-engine-src-path',
        shorebirdEnginePath,
        '--local-engine',
        // This is temporary because the Shorebird engine currently
        // only supports Android arm64.
        'android_release_arm64',
        ...results.rest
      ],
      runInShell: true,
    );

    process.stdout.listen((event) {
      logger.info(utf8.decode(event));
    });
    process.stderr.listen((event) {
      logger.err(utf8.decode(event));
    });

    return process.exitCode;
  }
}

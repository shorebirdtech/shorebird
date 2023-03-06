import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';

typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

/// {@template build_command}
///
/// `shorebird build`
/// Build a new release of your application.
/// {@endtemplate}
class BuildCommand extends Command<int> {
  /// {@macro build_command}
  BuildCommand({
    required Auth auth,
    required Logger logger,
    RunProcess? runProcess,
  })  : _auth = auth,
        _logger = logger,
        _runProcess = runProcess ?? Process.run;

  @override
  String get description => 'Build a new release of your application.';

  @override
  String get name => 'build';

  final Auth _auth;
  final Logger _logger;
  final RunProcess _runProcess;

  @override
  Future<int> run() async {
    final session = _auth.currentSession;
    if (session == null) {
      _logger
        ..err('You must be logged in to build.')
        ..err("Run 'shorebird login' to log in and try again.");
      return ExitCode.noUser.code;
    }

    final shorebirdEnginePath = p.join(
      Directory.current.path,
      '.shorebird',
      'engine',
    );
    final shorebirdEngineDir = Directory(shorebirdEnginePath);
    if (!shorebirdEngineDir.existsSync()) {
      _logger.err(
        'Shorebird engine not found. Run `shorebird run` to download it.',
      );
      return ExitCode.software.code;
    }

    final buildProgress = _logger.progress('Building release ');
    try {
      await _build(_runProcess, shorebirdEnginePath);
      buildProgress.complete();
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    return ExitCode.success.code;
  }

  Future<void> _build(RunProcess runProcess, String shorebirdEnginePath) async {
    const executable = 'flutter';
    final arguments = [
      'build',
      'apk',
      '--release',
      '--no-tree-shake-icons',
      '--local-engine-src-path',
      shorebirdEnginePath,
      '--local-engine',
      'android_release_arm64',
    ];

    final result = await runProcess(
      executable,
      arguments,
      runInShell: true,
    );

    if (result.exitCode != ExitCode.success.code) {
      throw ProcessException(
        'flutter',
        arguments,
        result.stderr.toString(),
        result.exitCode,
      );
    }
  }
}

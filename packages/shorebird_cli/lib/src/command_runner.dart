import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/engine_revision.dart';
import 'package:shorebird_cli/src/version.dart';

const executableName = 'shorebird';
const packageName = 'shorebird_cli';
const description = 'The shorebird command-line tool';

typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
  String? workingDirectory,
});

/// {@template shorebird_cli_command_runner}
/// A [CommandRunner] for the CLI.
///
/// ```
/// $ shorebird --version
/// ```
/// {@endtemplate}
class ShorebirdCliCommandRunner extends CompletionCommandRunner<int> {
  /// {@macro shorebird_cli_command_runner}
  ShorebirdCliCommandRunner({
    Logger? logger,
    RunProcess? runProcess,
  })  : _logger = logger ?? Logger(),
        _runProcess = runProcess ?? Process.run,
        super(executableName, description) {
    argParser
      ..addFlag(
        'version',
        abbr: 'v',
        negatable: false,
        help: 'Print the current version.',
      )
      ..addFlag(
        'verbose',
        help: 'Noisy logging, including all shell commands executed.',
      );

    addCommand(AppsCommand(logger: _logger));
    addCommand(BuildCommand(logger: _logger));
    addCommand(InitCommand(logger: _logger));
    addCommand(LoginCommand(logger: _logger));
    addCommand(LogoutCommand(logger: _logger));
    addCommand(PublishCommand(logger: _logger));
    addCommand(ReleaseCommand(logger: _logger));
    addCommand(RunCommand(logger: _logger));
    addCommand(UpgradeCommand(logger: _logger));
  }

  @override
  void printUsage() => _logger.info(usage);

  final Logger _logger;
  final RunProcess _runProcess;

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final topLevelResults = parse(args);
      if (topLevelResults['verbose'] == true) {
        _logger.level = Level.verbose;
      }

      try {
        final flutterEngineRevision = await _getFlutterEngineRevision();
        if (flutterEngineRevision != requiredFlutterEngineRevision) {
          _logger.err(
            '''
Shorebird only works with the latest stable channel at this time.

To use the latest stable channel, run:
  flutter channel stable
  flutter upgrade

If you believe you're already on the latest stable channel, please ask on Discord, we're happy to help!

Required engine revision: "$requiredFlutterEngineRevision"
Detected engine revision: "$flutterEngineRevision"''',
          );
          return ExitCode.software.code;
        }
      } catch (error) {
        _logger.err('Failed to get Flutter engine revision.\n$error');
        return ExitCode.software.code;
      }

      return await runCommand(topLevelResults) ?? ExitCode.success.code;
    } on FormatException catch (e, stackTrace) {
      // On format errors, show the commands error message, root usage and
      // exit with an error code
      _logger
        ..err(e.message)
        ..err('$stackTrace')
        ..info('')
        ..info(usage);
      return ExitCode.usage.code;
    } on UsageException catch (e) {
      // On usage errors, show the commands usage message and
      // exit with an error code
      _logger
        ..err(e.message)
        ..info('')
        ..info(e.usage);
      return ExitCode.usage.code;
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    // Fast track completion command
    if (topLevelResults.command?.name == 'completion') {
      await super.runCommand(topLevelResults);
      return ExitCode.success.code;
    }

    // Run the command or show version
    final int? exitCode;
    if (topLevelResults['version'] == true) {
      _logger.info(packageVersion);
      exitCode = ExitCode.success.code;
    } else {
      exitCode = await super.runCommand(topLevelResults);
    }

    return exitCode;
  }

  Future<String> _getFlutterEngineRevision() async {
    final result = await _runProcess(
      'flutter',
      ['--version'],
      runInShell: true,
    );
    if (result.exitCode != 0) throw Exception('${result.stderr}');

    final output = result.stdout as String;
    final regexp = RegExp(r'Engine • revision (.*?$)', multiLine: true);
    final flutterEngineRevision = regexp.firstMatch(output)?.group(1);
    if (flutterEngineRevision == null) {
      throw Exception('Unable to determine the Flutter engine revision.');
    }
    return flutterEngineRevision;
  }
}

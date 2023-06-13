import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/upgrader.dart';
import 'package:shorebird_cli/src/version.dart';

const executableName = 'shorebird';
const packageName = 'shorebird_cli';
const description = 'The shorebird command-line tool';

/// {@template shorebird_cli_command_runner}
/// A [CommandRunner] for the CLI.
///
/// ```
/// $ shorebird --version
/// ```
/// {@endtemplate}
class ShorebirdCliCommandRunner extends CompletionCommandRunner<int> {
  /// {@macro shorebird_cli_command_runner}
  ShorebirdCliCommandRunner() : super(executableName, description) {
    argParser
      ..addFlag(
        'version',
        negatable: false,
        help: 'Print the current version.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Noisy logging, including all shell commands executed.',
        callback: (verbose) {
          if (verbose) {
            logger.level = Level.verbose;
          }
        },
      )
      ..addOption(
        'local-engine-src-path',
        hide: true,
        help: 'Path to your engine src directory, if you are building Flutter '
            'locally.',
      )
      ..addOption(
        'local-engine',
        hide: true,
        help: 'Name of a build output within the engine out directory, if you '
            'are building Flutter locally.',
      );

    addCommand(AccountCommand());
    addCommand(AppsCommand());
    addCommand(BuildCommand());
    addCommand(CacheCommand());
    addCommand(CollaboratorsCommand());
    addCommand(DoctorCommand());
    addCommand(InitCommand());
    addCommand(LoginCommand());
    addCommand(LogoutCommand());
    addCommand(PatchCommand());
    addCommand(ReleaseCommand());
    addCommand(ReleasesCommand());
    addCommand(RunCommand());
    addCommand(SubscriptionCommand());
  }

  @override
  void printUsage() => logger.info(usage);

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final topLevelResults = parse(args);

      // Set up our context before running the command.
      final engineConfig = EngineConfig(
        localEngineSrcPath: topLevelResults['local-engine-src-path'] as String?,
        localEngine: topLevelResults['local-engine'] as String?,
      );
      final process = ShorebirdProcess(
        engineConfig: engineConfig,
        logger: logger,
      );

      return await runScoped<Future<int?>>(
            () => runCommand(topLevelResults),
            values: {
              engineConfigRef.overrideWith(() => engineConfig),
              processRef.overrideWith(() => process),
            },
          ) ??
          ExitCode.success.code;
    } on FormatException catch (e, stackTrace) {
      // On format errors, show the commands error message, root usage and
      // exit with an error code
      logger
        ..err(e.message)
        ..err('$stackTrace')
        ..info('')
        ..info(usage);
      return ExitCode.usage.code;
    } on UsageException catch (e) {
      // On usage errors, show the commands usage message and
      // exit with an error code
      logger
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

    var isUpToDate = true;
    try {
      logger.detail('[upgrader] Checking for updates...');
      isUpToDate = await upgrader.isUpToDate();
      logger.detail('[upgrader] isUpToDate: $isUpToDate');
    } catch (_) {
      logger.detail('[upgrader] Failed to check for updates: $_');
    }

    if (!isUpToDate) {
      final progress = logger.progress(
        'A new version of Shorebird is available! Upgrading',
      );
      try {
        await upgrader.upgrade();
        progress.complete();
        logger.detail('[upgrader] Upgrading complete.');
        final result = await process.run(
          Platform.script.path,
          topLevelResults.arguments,
          runInShell: true,
        );
        return result.exitCode;
      } catch (error) {
        logger.detail('[upgrader] Failed to upgrade: $error');
        progress.fail(error.toString());
      }
    }

    // Run the command or show version
    final int? exitCode;
    if (topLevelResults['version'] == true) {
      logger.info(
        '''
Shorebird $packageVersion
Shorebird Engine • revision ${ShorebirdEnvironment.shorebirdEngineRevision}''',
      );
      exitCode = ExitCode.success.code;
    } else {
      exitCode = await super.runCommand(topLevelResults);
    }

    return exitCode;
  }
}

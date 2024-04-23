import 'dart:async';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';
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
      )
      ..addOption(
        'local-engine-host',
        hide: true,
        help: 'The build of the local engine to use as the host platform.',
      );

    addCommand(BuildCommand());
    addCommand(CacheCommand());
    addCommand(DoctorCommand());
    addCommand(FlutterCommand());
    addCommand(InitCommand());
    addCommand(LoginCommand());
    addCommand(LoginCiCommand());
    addCommand(LogoutCommand());
    addCommand(PatchCommand());
    addCommand(PreviewCommand());
    addCommand(ReleaseCommand());
    addCommand(RunCommand());
    addCommand(UpgradeCommand());
  }

  @override
  void printUsage() => logger.info(usage);

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final topLevelResults = parse(args);

      final localEngineSrcPath =
          topLevelResults['local-engine-src-path'] as String?;
      final localEngine = topLevelResults['local-engine'] as String?;
      final localEngineHost = topLevelResults['local-engine-host'] as String?;

      final localEngineArgs = [
        localEngineSrcPath,
        localEngine,
        localEngineHost,
      ];
      final localEngineArgsAreNull =
          localEngineArgs.every((arg) => arg == null);
      final localEngineArgsAreNotNull =
          localEngineArgs.every((arg) => arg != null);
      final EngineConfig engineConfig;
      if (localEngineArgsAreNotNull) {
        engineConfig = EngineConfig(
          localEngineSrcPath: localEngineSrcPath,
          localEngine: localEngine,
          localEngineHost: localEngineHost,
        );
      } else if (localEngineArgsAreNull) {
        engineConfig = const EngineConfig.empty();
      } else {
        // Only some local engine args were provided, this is invalid.
        throw ArgumentError(
          '''local-engine, local-engine-src, and local-engine-host must all be provided''',
        );
      }

      final process = ShorebirdProcess();
      final shorebirdArtifacts = engineConfig.localEngineSrcPath != null
          ? const ShorebirdLocalEngineArtifacts()
          : const ShorebirdCachedArtifacts();
      return await runScoped<Future<int?>>(
            () => runCommand(topLevelResults),
            values: {
              engineConfigRef.overrideWith(() => engineConfig),
              processRef.overrideWith(() => process),
              shorebirdArtifactsRef.overrideWith(() => shorebirdArtifacts),
            },
          ) ??
          ExitCode.success.code;
    } on FormatException catch (e, stackTrace) {
      // On format errors, show the commands error message, root usage and
      // exit with an error code
      logger
        ..err(e.message)
        ..detail('$stackTrace')
        ..info('')
        ..info(usage);
      return ExitCode.usage.code;
    } on UsageException catch (e) {
      // On usage errors, show the commands usage message and
      // exit with an error code

      logger.err(e.message);
      if (e.message.contains('Could not find an option named')) {
        final String errorMessage;
        if (platform.isWindows) {
          errorMessage = '''
To proxy an option to the flutter command, use the '--' --<option> syntax.

Example:

${lightCyan.wrap("shorebird release android '--' --no-pub lib/main.dart")}''';
        } else {
          errorMessage = '''
To proxy an option to the flutter command, use the -- --<option> syntax.

Example:

${lightCyan.wrap('shorebird release android -- --no-pub lib/main.dart')}''';
        }

        logger.err(errorMessage);
      }

      logger
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
    int? exitCode;
    if (topLevelResults['version'] == true) {
      final flutterVersion = await _tryGetFlutterVersion();
      final shorebirdFlutterPrefix = StringBuffer('Flutter');
      if (flutterVersion != null) {
        shorebirdFlutterPrefix.write(' $flutterVersion');
      }
      logger.info('''
Shorebird $packageVersion • git@github.com:shorebirdtech/shorebird.git
$shorebirdFlutterPrefix • revision ${shorebirdEnv.flutterRevision}
Engine • revision ${shorebirdEnv.shorebirdEngineRevision}''');

      try {
        final isUpToDate = await shorebirdVersion.isLatest();
        if (!isUpToDate) {
          logger.info('''
A new version of shorebird is available!
Run ${lightCyan.wrap('shorebird upgrade')} to upgrade.''');
        }
      } catch (error) {
        logger.detail('Unable to check for updates.\n$error');
      }
      exitCode = ExitCode.success.code;
    } else {
      try {
        // Most commands need shorebird artifacts, so we ensure the cache
        // is up to date for all commands (even ones which don't need it).  We
        // could make a Command subclass and move the cache onto that and
        // only update in that case, but it didn't seem worth it at the time.
        // Ensure all cached artifacts are up-to-date before running the
        // command.
        await cache.updateAll();
        exitCode = await super.runCommand(topLevelResults);
      } catch (error, stackTrace) {
        logger
          ..err('$error')
          ..detail('$stackTrace');
        exitCode = ExitCode.software.code;
      }
    }

    if (exitCode == ExitCode.software.code && logger.level != Level.verbose) {
      logger.info(
        '''

If you aren't sure why this command failed, re-run with the ${lightCyan.wrap('--verbose')} flag to see more information.''',
      );
    }

    return exitCode;
  }

  Future<String?> _tryGetFlutterVersion() async {
    try {
      return await shorebirdFlutter.getVersionString();
    } catch (error) {
      logger.detail('Unable to determine Flutter version.\n$error');
      return null;
    }
  }
}

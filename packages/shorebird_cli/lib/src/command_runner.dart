import 'dart:async';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
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
      await preprocess(args);
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
    final int? exitCode;
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
      exitCode = ExitCode.success.code;
    } else {
      exitCode = await super.runCommand(topLevelResults);
    }

    return exitCode;
  }

  Future<String?> _tryGetFlutterVersion() async {
    try {
      return await shorebirdFlutter.getVersion();
    } catch (error) {
      logger.detail('Unable to determine Flutter version.\n$error');
      return null;
    }
  }
}

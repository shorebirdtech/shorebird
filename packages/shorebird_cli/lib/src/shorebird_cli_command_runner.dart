import 'dart:async';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version.dart';

/// The name of the executable.
const executableName = 'shorebird';

/// The name of the package (e.g. name in the pubspec.yaml).
const packageName = 'shorebird_cli';

/// The package description.
const description = 'The shorebird command-line tool';

/// {@template shorebird_cli_command_runner}
/// A [CommandRunner] for the CLI.
///
/// ```sh
/// $ shorebird --version
/// ```
/// {@endtemplate}
class ShorebirdCliCommandRunner extends CompletionCommandRunner<int> {
  /// {@macro shorebird_cli_command_runner}
  ShorebirdCliCommandRunner() : super(executableName, description) {
    argParser
      ..addFlag('version', negatable: false, help: 'Print the current version.')
      ..addFlag(
        'json',
        negatable: false,
        help: 'Output results in JSON format.',
      )
      ..addFlag(
        'no-input',
        negatable: false,
        help:
            'Disable interactive prompts. Fails with an actionable error when '
            'input would otherwise be required.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Noisy logging, including all shell commands executed.',
      )
      ..addOption(
        'local-engine-src-path',
        hide: true,
        help:
            'Path to your engine src directory, if you are building Flutter '
            'locally.',
      )
      ..addOption(
        'local-engine',
        hide: true,
        help:
            'Name of a build output within the engine out directory, if you '
            'are building Flutter locally.',
      )
      ..addOption(
        'local-engine-host',
        hide: true,
        help: 'The build of the local engine to use as the host platform.',
      );

    addCommand(CacheCommand());
    addCommand(CreateCommand());
    addCommand(DoctorCommand());
    addCommand(FlutterCommand());
    addCommand(InitCommand());
    addCommand(LoginCommand());
    addCommand(LoginCiCommand());
    addCommand(LogoutCommand());
    addCommand(PatchCommand());
    addCommand(PatchesCommand());
    addCommand(PreviewCommand());
    addCommand(ReleaseCommand());
    addCommand(ReleasesCommand());
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
      final localEngineArgsAreNull = localEngineArgs.every(
        (arg) => arg == null,
      );
      final localEngineArgsAreNotNull = localEngineArgs.every(
        (arg) => arg != null,
      );
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

      final jsonMode = topLevelResults['json'] == true;
      final noInputMode = topLevelResults['no-input'] == true;

      // In JSON mode, suppress verbose logging — it writes to stdout and
      // would corrupt the JSON output. Verbose output still goes to the
      // log file via ShorebirdLogger.detail.
      if (!jsonMode && topLevelResults['verbose'] == true) {
        logger.level = Level.verbose;
      }

      final process = ShorebirdProcess();
      final shorebirdArtifacts = engineConfig.localEngineSrcPath != null
          ? const ShorebirdLocalEngineArtifacts()
          : const ShorebirdCachedArtifacts();
      return await runScoped<Future<int?>>(
            () => runCommand(topLevelResults),
            values: {
              engineConfigRef.overrideWith(() => engineConfig),
              isJsonModeRef.overrideWith(() => jsonMode),
              isNoInputModeRef.overrideWith(() => noInputMode),
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

    final commandName = commandNameFromResults(topLevelResults);

    // Run the command or show version
    int? exitCode;
    if (topLevelResults['version'] == true) {
      final flutterVersion = await _tryGetFlutterVersion();
      if (isJsonMode) {
        JsonResult.success(
          data: {
            'shorebird_version': packageVersion,
            'flutter_version': flutterVersion,
            'flutter_revision': shorebirdEnv.flutterRevision,
            'engine_revision': shorebirdEnv.shorebirdEngineRevision,
          },
          command: 'version',
        ).write();
      } else {
        final shorebirdFlutterPrefix = StringBuffer('Flutter');
        if (flutterVersion != null) {
          shorebirdFlutterPrefix.write(' $flutterVersion');
        }
        logger.info('''
Shorebird $packageVersion • git@github.com:shorebirdtech/shorebird.git
$shorebirdFlutterPrefix • revision ${shorebirdEnv.flutterRevision}
Engine • revision ${shorebirdEnv.shorebirdEngineRevision}''');
      }
      exitCode = ExitCode.success.code;
    } else {
      try {
        exitCode = await super.runCommand(topLevelResults);
      } on ProcessExit catch (error) {
        exitCode = error.exitCode;
        if (isJsonMode && error.exitCode != ExitCode.success.code) {
          JsonResult.error(
            code: JsonErrorCode.processExit,
            message: 'Process exited with code ${error.exitCode}.',
            command: commandName,
          ).write();
        }
      } on UsageException catch (e) {
        if (isJsonMode) {
          JsonResult.error(
            code: JsonErrorCode.usageError,
            message: e.message,
            hint: 'Run: shorebird $commandName --help',
            command: commandName,
          ).write();
        } else {
          logger
            ..err(e.message)
            ..info(e.usage);
        }
        // When on an usage exception we don't need to show the "if you aren't
        // sure" message, so we do an early return here.
        return ExitCode.usage.code;
      } on InteractivePromptRequiredException catch (e) {
        if (isJsonMode) {
          JsonResult.error(
            code: JsonErrorCode.interactivePromptRequired,
            message: e.promptText,
            hint: e.hint,
            command: commandName,
          ).write();
        } else {
          logger
            ..err(
              'Input was required for the following prompt but the CLI is '
              'running in a non-interactive context:',
            )
            ..err('  ${e.promptText}')
            ..info('')
            ..info('Hint: ${e.hint}');
        }
        return ExitCode.usage.code;

        // We explicitly want to catch all exceptions here to log them and show
        // the user a friendly message.
        // ignore: avoid_catches_without_on_clauses
      } catch (error, stackTrace) {
        if (isJsonMode) {
          JsonResult.error(
            code: JsonErrorCode.softwareError,
            message: '$error',
            command: commandName,
          ).write();
        }
        logger
          ..err('$error')
          ..detail('$stackTrace');
        exitCode = ExitCode.software.code;
      }
    }

    // `runCommand` returns null in when the --help flag is passed.
    if (!isJsonMode &&
        exitCode != null &&
        exitCode != ExitCode.success.code &&
        logger.level != Level.verbose) {
      final fileAnIssue = link(
        uri: Uri.parse(
          'https://github.com/shorebirdtech/shorebird/issues/new/choose',
        ),
        message: 'file an issue',
      );
      logger.info('''

If you aren't sure why this command failed, re-run with the ${lightCyan.wrap('--verbose')} flag to see more information.

You can also $fileAnIssue if you think this is a bug. Please include the following log file in your report:
${currentRunLogFile.absolute.path}
''');
    }

    if (!isJsonMode &&
        topLevelResults.command?.name != UpgradeCommand.commandName) {
      await _checkForUpdates();
    }

    return exitCode;
  }

  Future<String?> _tryGetFlutterVersion() async {
    try {
      return await shorebirdFlutter.getVersionString();
    } on Exception catch (error) {
      logger.detail('Unable to determine Flutter version.\n$error');
      return null;
    }
  }

  /// If this version of shorebird is on the `stable` branch, checks to see if
  /// there are newer commits available. If there are, prints a message to the
  /// user telling them to run `shorebird upgrade`.
  Future<void> _checkForUpdates() async {
    try {
      if (await shorebirdVersion.isTrackingStable() &&
          !await shorebirdVersion.isLatest()) {
        logger
          ..info('')
          ..info('A new version of shorebird is available!')
          ..info('Run ${lightCyan.wrap('shorebird upgrade')} to upgrade.');
      }
    } on Exception catch (error) {
      logger.detail('Unable to check for updates.\n$error');
    }
  }
}

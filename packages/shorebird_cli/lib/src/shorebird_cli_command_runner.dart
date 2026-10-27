import 'dart:async';
import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/engine_config.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version_info.dart';

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
        help: 'Output results in JSON format (implies non-interactive mode).',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Noisy logging, including all shell commands executed.',
      )
      ..addFlag(
        'dev',
        negatable: false,
        hide: true,
        help:
            'Use the Shorebird dev environment ($devHostedUrl and '
            '$devAuthServiceUrl). SHOREBIRD_HOSTED_URL and AUTH_SERVICE_URL '
            'still win.',
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

    addCommand(AccountCommand());
    addCommand(ApiCommand());
    addCommand(AppsCommand());
    addCommand(AuthCommand());
    addCommand(CacheCommand());
    addCommand(ChannelsCommand());
    addCommand(CreateCommand());
    addCommand(DoctorCommand());
    addCommand(FlutterCommand());
    addCommand(InitCommand());
    addCommand(InvitationsCommand());
    addCommand(LoginCommand());
    addCommand(LoginCiCommand());
    addCommand(LogoutCommand());
    addCommand(TopLevelMembersCommand());
    addCommand(MetricsCommand());
    addCommand(OrgsCommand());
    addCommand(PatchCommand());
    addCommand(PatchesCommand());
    addCommand(PreviewCommand());
    addCommand(ReleaseCommand());
    addCommand(ReleasesCommand());
    addCommand(TokensCommand());
    addCommand(UpgradeCommand());
    addCommand(TopLevelWhoamiCommand());
  }

  @override
  void printUsage() => logger.info(usage);

  /// [results], or, when they name a command with a
  /// [ShorebirdCommand.defaultSubcommand] and no subcommand, arguments, or
  /// `--help`, [args] parsed again with that subcommand added, so that a bare
  /// `shorebird account` runs `shorebird account whoami`.
  ArgResults _withDefaultSubcommand(List<String> args, ArgResults results) {
    var commands = this.commands;
    var next = results.command;
    while (next != null) {
      final command = commands[next.name];
      if (command == null) return results;
      if (next.command == null) {
        // After `--`, an added subcommand would be read as an argument.
        if (command is! ShorebirdCommand ||
            next.rest.isNotEmpty ||
            args.contains('--') ||
            (next.options.contains('help') && next.flag('help'))) {
          return results;
        }
        final subcommand = command.defaultSubcommand;
        if (subcommand == null) return results;
        return parse([...args, subcommand]);
      }
      commands = command.subcommands;
      next = next.command;
    }
    return results;
  }

  @override
  Future<int> run(Iterable<String> args) async {
    final argsList = args.toList();
    // Detect `--json` from the raw argv so that parse-time failures
    // (unknown flags, malformed input) can still emit a JSON envelope.
    // `parse(args)` throws before we'd otherwise read this flag.
    final jsonModeFromArgs = argsList.contains('--json');

    try {
      final topLevelResults = _withDefaultSubcommand(
        argsList,
        parse(argsList),
      );

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
        usageException(
          '''--local-engine, --local-engine-src-path, and --local-engine-host must all be provided together''',
        );
      }

      final jsonMode = topLevelResults['json'] == true;
      final devMode = topLevelResults['dev'] == true;

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
      // In JSON mode stdout carries the envelope and nothing else. Both
      // sinks are bound here, outside the redirect below: the envelope goes
      // to the real stdout, and everything else that would have reached
      // stdout (human log lines, progress) goes to stderr, where a caller
      // parsing stdout as JSON will not trip over it. Subprocess output
      // takes a second path to the same place -- a child started with
      // `inheritStdio` writes to our real fd 1, past any `IOOverrides`, so
      // `ShorebirdProcess.stream` pipes instead in JSON mode and forwards
      // the child's bytes to stderr itself.
      final jsonSink = io.stdout;
      final humanSink = io.stderr;
      // Suppress ANSI escape codes when the user has opted into a
      // non-interactive output mode. When stdout/stderr aren't TTYs the io
      // package already disables ANSI automatically.
      Future<int?> runWithRefs() => runScoped<Future<int?>>(
        () => runCommand(topLevelResults),
        values: {
          engineConfigRef.overrideWith(() => engineConfig),
          isDevModeRef.overrideWith(() => devMode),
          isJsonModeRef.overrideWith(() => jsonMode),
          jsonSinkRef.overrideWith(() => jsonSink),
          processRef.overrideWith(() => process),
          shorebirdArtifactsRef.overrideWith(() => shorebirdArtifacts),
        },
      );
      final exitCode = jsonMode
          ? await overrideAnsiOutput<Future<int?>>(
              false,
              () => io.IOOverrides.runZoned(
                runWithRefs,
                stdout: () => humanSink,
              ),
            )
          : await runWithRefs();
      return exitCode ?? ExitCode.success.code;
    } on FormatException catch (e, stackTrace) {
      // On format errors, show the commands error message, root usage and
      // exit with an error code
      // FormatException from `parse(args)` is rare in practice; the JSON
      // branch is hard to trigger from real argv.
      // coverage:ignore-start
      if (jsonModeFromArgs) {
        JsonResult.error(
          code: JsonErrorCode.usageError,
          message: e.message,
          hint: 'Run: shorebird --help',
          command: executableName,
        ).write();
      } else {
        // coverage:ignore-end
        logger
          ..err(e.message)
          ..detail('$stackTrace')
          ..info('')
          ..info(usage);
      }
      return ExitCode.usage.code;
    } on UsageException catch (e) {
      // On usage errors, show the commands usage message and
      // exit with an error code
      final unknownOption = _unknownOptionName(e.message);
      final hint = unknownOption == null
          ? null
          : _unknownOptionHint(unknownOption, argsList);

      if (jsonModeFromArgs) {
        JsonResult.error(
          code: JsonErrorCode.usageError,
          message: e.message,
          hint: hint ?? 'Run: shorebird --help',
          command: executableName,
        ).write();
        return ExitCode.usage.code;
      }

      logger.err(e.message);
      if (hint != null) logger.err(hint);

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

    final commandName =
        commandNameFromResults(topLevelResults) ?? executableName;

    // Run the command or show version
    int? exitCode;
    // A declined prompt already said what was not done, so it gets no
    // "re-run with --verbose" footer.
    var declined = false;
    if (topLevelResults['version'] == true) {
      final flutterVersion = await tryGetFlutterVersion();
      if (isJsonMode) {
        JsonResult.success(
          data: versionJson(flutterVersion: flutterVersion),
          command: 'version',
        ).write();
      } else {
        logger.info(versionBanner(flutterVersion: flutterVersion));
      }
      exitCode = ExitCode.success.code;
    } else {
      // Records whether the command wrote its own envelope, so that a failing
      // --json command always leaves exactly one on stdout: the command's if
      // it wrote one, otherwise the runner's.
      final envelope = JsonEnvelopeTracker();
      final aliasNotice = _aliasNotice(topLevelResults);
      // Under --json, human lines already go to stderr, so the notice
      // never reaches the envelope.
      if (aliasNotice != null) {
        if (_reservesStdout(topLevelResults)) {
          await runWithStdoutOnStderr(() async => logger.info(aliasNotice));
        } else {
          logger.info(aliasNotice);
        }
      }
      try {
        exitCode = await runScoped(
          () => super.runCommand(topLevelResults),
          values: {
            jsonEnvelopeTrackerRef.overrideWith(() => envelope),
          },
        );
        // A command that fails by returning an exit code (a failed
        // precondition, say) may not have written an envelope. Write the
        // same one a thrown ProcessExit gets.
        if (isJsonMode &&
            !envelope.written &&
            exitCode != null &&
            exitCode != ExitCode.success.code) {
          JsonResult.error(
            code: JsonErrorCode.processExit,
            message: 'Process exited with code $exitCode.',
            command: commandName,
          ).write();
        }
      } on ProcessExit catch (error) {
        exitCode = error.exitCode;
        declined = error is PromptDeclinedExit;
        if (isJsonMode &&
            !envelope.written &&
            error.exitCode != ExitCode.success.code) {
          // A failed precondition says why, not just that the process exited,
          // and so does a failed API call.
          final failure = error is PreconditionFailedExit
              ? error.failure
              : null;
          final apiError = error is ApiErrorExit ? error.error : null;
          JsonResult.error(
            code: failure == null
                ? JsonErrorCode.processExit
                : JsonErrorCode.preconditionFailed,
            message:
                failure?.message ??
                apiError?.message ??
                'Process exited with code ${error.exitCode}.',
            hint: failure?.hint,
            apiCode: apiError?.code,
            details: apiError?.details,
            documentationUrl: apiError?.documentationUrl,
            command: commandName,
          ).write();
        }
      } on UsageException catch (e) {
        if (isJsonMode) {
          if (envelope.written) return ExitCode.usage.code;
          final subcommand = commandNameFromResults(topLevelResults);
          final hint = subcommand == null
              ? 'Run: shorebird --help'
              : 'Run: shorebird $subcommand --help'; // coverage:ignore-line
          JsonResult.error(
            code: JsonErrorCode.usageError,
            message: e.message,
            hint: hint,
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
          if (envelope.written) return ExitCode.usage.code;
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
        if (isJsonMode && !envelope.written) {
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
      // Every --json run leaves exactly one envelope on stdout. A command
      // that succeeded without writing one (it has no JSON output, or it only
      // printed usage for --help, where the exit code is null) gets an empty
      // success envelope.
      if (isJsonMode &&
          !envelope.written &&
          (exitCode == null || exitCode == ExitCode.success.code)) {
        JsonResult.success(data: const {}, command: commandName).write();
      }
    }

    final reservesStdout = _reservesStdout(topLevelResults);

    // `runCommand` returns null in when the --help flag is passed.
    if (!isJsonMode &&
        !reservesStdout &&
        !declined &&
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

    if (reservesStdout) {
      await runWithStdoutOnStderr(() async => _pruneUnusedCaches());
    } else {
      _pruneUnusedCaches();
    }

    if (!isJsonMode &&
        topLevelResults.command?.name != UpgradeCommand.commandName) {
      if (reservesStdout) {
        await runWithStdoutOnStderr(_checkForUpdates);
      } else {
        await _checkForUpdates();
      }
    }

    return exitCode;
  }

  /// Names the canonical command when [topLevelResults] reached its command
  /// through an alias (`shorebird cache clear` for `shorebird cache clean`),
  /// so that whoever guessed the alias learns the name the docs use. Null
  /// when every name typed was the command's own.
  String? _aliasNotice(ArgResults topLevelResults) {
    final typed = <String>[];
    final canonical = <String>[];
    var available = commands;
    for (
      var results = topLevelResults.command;
      results != null;
      results = results.command
    ) {
      final name = results.name!;
      final command = available[name];
      if (command == null) return null;
      typed.add(name);
      canonical.add(command.name);
      available = command.subcommands;
    }
    if (const ListEquality<String>().equals(typed, canonical)) return null;
    return '`$executableName ${typed.join(' ')}` is an alias of '
        '`$executableName ${canonical.join(' ')}`.';
  }

  /// Whether the command [topLevelResults] ran is a [ShorebirdCommand] whose
  /// output owns stdout (see [ShorebirdCommand.reservesStdout]).
  bool _reservesStdout(ArgResults topLevelResults) {
    Command<int>? command;
    var available = commands;
    for (
      var results = topLevelResults.command;
      results != null;
      results = results.command
    ) {
      command = available[results.name];
      if (command == null) return false;
      available = command.subcommands;
    }
    return command is ShorebirdCommand && command.reservesStdout;
  }

  /// Removes Flutter installs, engine artifacts and previews that have gone
  /// unused, so they do not pile up across upgrades, `--flutter-version`
  /// builds and previewed releases (shorebirdtech/shorebird#3976).
  ///
  /// Runs after the command so that what it used is already recorded as used,
  /// and so that after `shorebird upgrade` the new pin is the one protected.
  /// Never fails the command.
  void _pruneUnusedCaches() {
    final pruners = {
      'Flutter installs': shorebirdFlutter.pruneUnusedRevisions,
      'artifacts': cache.pruneUnusedArtifacts,
      'previews': cache.pruneUnusedPreviews,
      'release artifacts': cache.pruneUnusedReleaseArtifacts,
    };
    for (final MapEntry(key: name, value: prune) in pruners.entries) {
      try {
        prune();
        // Pruning is housekeeping; nothing it hits should change the outcome
        // of the command the user ran.
        // ignore: avoid_catches_without_on_clauses
      } catch (error) {
        logger.detail('Unable to prune unused $name.\n$error');
      }
    }
  }

  /// The option name (without leading dashes) from an args-package
  /// "Could not find an option named" message, or null for other messages.
  static String? _unknownOptionName(String message) {
    final match = RegExp(
      'Could not find an option named "(?:--)?([^"]+)"',
    ).firstMatch(message);
    return match?.group(1);
  }

  /// Option names people reach for to bypass a safety check.
  static final _safetyOverridePattern = RegExp(
    r'^(?:f|y|force|yes)$|allow|skip|ignore',
  );

  /// The hint to print under an unknown-option error.
  ///
  /// `shorebird patch --force` (or any override-shaped option) gets the
  /// flags that actually bypass the patch safety checks; everything else
  /// gets the `--` pass-through explanation.
  String _unknownOptionHint(String option, List<String> args) {
    final commandName = args.where((a) => !a.startsWith('-')).firstOrNull;
    if (commandName == 'patch' && _safetyOverridePattern.hasMatch(option)) {
      return '''
shorebird patch has no --$option flag. The patch safety checks are bypassed per check:
  ${lightCyan.wrap('--allow-native-diffs')}  publish even though native code changed
  ${lightCyan.wrap('--allow-asset-diffs')}   publish even though assets changed
The warning that fails the patch names the one that applies.''';
    }

    final separator = platform.isWindows ? "'--'" : '--';
    return '''
To proxy an option to the flutter command, use the $separator --<option> syntax.

Example:

${lightCyan.wrap("shorebird release android $separator --no-pub lib/main.dart")}''';
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

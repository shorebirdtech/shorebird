import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/interactive_mode.dart' as interactive_mode;
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_cli_command_runner.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Signature for a function which takes a path to a zip file.
typedef UnzipFn = Future<void> Function(String zipFilePath, String outputDir);

/// Signature for a function which builds a [CodePushClient].
typedef CodePushClientBuilder =
    CodePushClient Function({required http.Client httpClient, Uri? hostedUri});

/// {@template shorebird_command}
/// A command in the Shorebird CLI.
/// {@endtemplate}
abstract class ShorebirdCommand extends Command<int> {
  // We don't currently have a test involving both a CommandRunner
  // and a Command, so we can't test this getter.
  // coverage:ignore-start
  @override
  ShorebirdCliCommandRunner? get runner =>
      testRunner ?? super.runner as ShorebirdCliCommandRunner?;
  // coverage:ignore-end

  /// [ArgResults] used for testing purposes only.
  @visibleForTesting
  ArgResults? testArgResults;

  /// The parent command runner used for testing purposes only.
  @visibleForTesting
  ShorebirdCliCommandRunner? testRunner;

  /// [ArgResults] for the current command.
  ArgResults get results => testArgResults ?? argResults!;

  /// Prints usage through the logger rather than `print`, which writes to
  /// the real stdout. Under `--json`, the logger's output goes to stderr and
  /// stdout carries only the envelope.
  @override
  void printUsage() => logger.info(usage);

  /// Whether stdout carries only this command's output, such as the response
  /// body `shorebird api` prints.
  ///
  /// When true, the command runner keeps its own messages (the hint printed
  /// after a failure, the notice that an upgrade is available) off stdout:
  /// the failure hint is skipped, since the command reports its own errors,
  /// and the upgrade notice goes to stderr.
  bool get reservesStdout => false;

  /// The subcommand that runs when this command is given none, such as
  /// `whoami` for a bare `shorebird account`, or null to print usage as
  /// usual.
  String? get defaultSubcommand => null;

  /// Whether the `--json` global flag was passed.
  ///
  /// Reads from the [isJsonModeRef] scoped dependency, which is set by the
  /// command runner based on the parsed `--json` flag.
  bool get isJsonMode => read(isJsonModeRef);

  // isInteractive is a thin wrapper around the top-level getter in
  // `interactive_mode.dart`, which is directly tested via the runner's
  // "interactive mode" matrix. Exercising it through a ShorebirdCommand
  // subclass would just re-run the same predicate with no additional value.
  // coverage:ignore-start
  /// Whether the CLI is running in an interactive context.
  ///
  /// `false` when stdout is not a terminal or when `--json` was passed.
  /// See [interactive_mode.isInteractive].
  bool get isInteractive => interactive_mode.isInteractive;
  // coverage:ignore-end

  /// The release types named by the positional platform or `--platforms`.
  ///
  /// Throws a [UsageException] when no platform was given, the platform is
  /// not valid, or an extra positional argument was passed. When the invalid
  /// platform is a subcommand of [siblingCommand] (e.g. `rollback` under
  /// `patches`), the message points there.
  Iterable<ReleaseType> releaseTypesOrUsageError({
    required String siblingCommand,
  }) {
    final List<ReleaseType> types;
    try {
      types = results.releaseTypes.toList();
    } on PlatformArgumentException catch (e) {
      final positional = results.rest.firstOrNull;
      final sibling = runner!.commands[siblingCommand];
      if (positional != null &&
          (sibling?.subcommands.containsKey(positional) ?? false)) {
        usageException(
          '''
${e.message}
Did you mean "shorebird $siblingCommand $positional"?''',
        );
      }
      usageException(e.message);
    }
    if (types.isEmpty) {
      usageException(
        '''
No platform was provided.
Valid platforms: $validPlatformNames''',
      );
    }
    return types;
  }

  /// The full command name including parent commands (e.g. "releases list").
  String get fullCommandName {
    final parts = <String>[];
    Command<int>? current = this;
    while (current != null) {
      parts.insert(0, current.name);
      current = current.parent;
    }
    return parts.join(' ');
  }

  /// Emits a JSON success envelope with the given [data] to stdout.
  ///
  /// Only call this when [isJsonMode] is true.
  void emitJsonSuccess(Map<String, dynamic> data) {
    JsonResult.success(data: data, command: fullCommandName).write();
  }

  /// Suffix appended to command descriptions to advertise `--json` mode.
  ///
  /// [example] should be a complete example invocation, e.g.:
  ///   `'shorebird releases list --app-id <id> --json'`
  static String jsonHint(String example) =>
      'Pass --json (global flag) for machine-readable output with all fields:\n'
      '  $example';

  /// Validates the patch-signing arguments.
  ///
  /// Valid configurations:
  /// - No signing (nothing provided)
  /// - File-based: --public-key-path + --private-key-path
  /// - Command-based: --public-key-cmd + --sign-cmd
  /// - Mixed: --public-key-path + --sign-cmd
  ///
  /// Anything else is a usage error whose message names the flag to add,
  /// drop, or fix.
  void assertSigningArgsValid() {
    final publicKeyPath = CommonArguments.publicKeyArg.name;
    final privateKeyPath = CommonArguments.privateKeyArg.name;
    final publicKeyCmd = CommonArguments.publicKeyCmd.name;
    final signCmd = CommonArguments.signCmd.name;

    final hasPublicKeyFile = results.wasParsed(publicKeyPath);
    final hasPrivateKeyFile = results.wasParsed(privateKeyPath);
    final hasPublicKeyCmd = results.wasParsed(publicKeyCmd);
    final hasSignCmd = results.wasParsed(signCmd);

    if (hasPublicKeyFile && hasPublicKeyCmd) {
      usageException(
        'Pass either --$publicKeyPath or --$publicKeyCmd, not both.',
      );
    }
    if (hasPrivateKeyFile && hasSignCmd) {
      usageException('Pass either --$privateKeyPath or --$signCmd, not both.');
    }
    if (hasSignCmd && !hasPublicKeyFile && !hasPublicKeyCmd) {
      usageException(
        '--$signCmd requires a public key: add --$publicKeyPath=<path> or '
        '--$publicKeyCmd=<command>.',
      );
    }
    // File-based signing needs both files.
    if (hasPublicKeyFile != hasPrivateKeyFile && !hasSignCmd) {
      final missing = hasPublicKeyFile ? privateKeyPath : publicKeyPath;
      usageException(
        '--$publicKeyPath and --$privateKeyPath must be passed together '
        '(missing --$missing).',
      );
    }
    _assertFileArgExists(publicKeyPath);
    _assertFileArgExists(privateKeyPath);
  }

  /// Validates the release-signing arguments: at most one public key source,
  /// and if it is a file, the file exists.
  void assertPublicKeyArgsValid() {
    final publicKeyPath = CommonArguments.publicKeyArg.name;
    final publicKeyCmd = CommonArguments.publicKeyCmd.name;
    if (results.wasParsed(publicKeyPath) && results.wasParsed(publicKeyCmd)) {
      usageException(
        'Pass either --$publicKeyPath or --$publicKeyCmd, not both.',
      );
    }
    _assertFileArgExists(publicKeyPath);
  }

  /// Usage error unless the file passed to the option [name] exists. Does
  /// nothing when the option was not provided.
  void _assertFileArgExists(String name) {
    final path = results[name] as String?;
    if (path != null && !File(path).existsSync()) {
      usageException('--$name: no file found at $path.');
    }
  }

  /// Emits a JSON error envelope to stdout.
  ///
  /// Only call this when [isJsonMode] is true.
  void emitJsonError({
    required JsonErrorCode code,
    required String message,
    String? hint,
    String? apiCode,
    String? details,
  }) {
    JsonResult.error(
      code: code,
      message: message,
      hint: hint,
      apiCode: apiCode,
      details: details,
      command: fullCommandName,
    ).write();
  }

  /// Reports an error in whichever output mode is active and returns
  /// [exitCode] (a usage error by default).
  ///
  /// With `--json`, emits an error envelope carrying [code], [message] and
  /// [hint]. Otherwise logs [message] as an error and [hint], if any, as
  /// info. Both modes report the same [message].
  int reportError({
    required String message,
    String? hint,
    JsonErrorCode code = JsonErrorCode.usageError,
    int? exitCode,
  }) {
    if (isJsonMode) {
      emitJsonError(code: code, message: message, hint: hint);
    } else {
      logger.err(message);
      if (hint != null) logger.info(hint);
    }
    return exitCode ?? ExitCode.usage.code;
  }

  /// Reports [error], a failed Shorebird API call, in whichever output mode is
  /// active and returns [ExitCode.software].
  ///
  /// [message] says what failed (e.g. "Failed to fetch patch installs.") and
  /// is followed by the server's own message. The server's error code and
  /// details, when present, are reported too: as `api_code` and `details` in
  /// the `--json` error envelope (whose `code` is [code]), and as extra lines
  /// otherwise. This lets a caller tell, for example, a plan that lacks a
  /// feature (`shorebird_plan_insufficient_tier`) from a missing resource.
  int reportApiError(
    CodePushException error, {
    required String message,
    JsonErrorCode code = JsonErrorCode.fetchFailed,
  }) {
    final fullMessage = '$message ${error.message}';
    if (isJsonMode) {
      emitJsonError(
        code: code,
        message: fullMessage,
        apiCode: error.code,
        details: error.details,
      );
    } else {
      logger.err(fullMessage);
      if (error.details case final details?) logger.info(details);
      if (error.code case final apiCode?) logger.info('Error code: $apiCode');
    }
    return ExitCode.software.code;
  }

  /// Reports a failed precondition and returns its exit code.
  ///
  /// The explanation was already logged when [error] was thrown, so in human
  /// mode there is nothing more to print. With `--json`, emits a
  /// `precondition_failed` envelope carrying [error]'s message and hint, so a
  /// caller reading only stdout learns why (logged out, not in a project,
  /// ...), not just the exit code.
  int reportPreconditionFailure(PreconditionFailedException error) {
    if (isJsonMode) {
      emitJsonError(
        code: JsonErrorCode.preconditionFailed,
        message: error.message,
        hint: error.hint,
      );
    }
    return error.exitCode.code;
  }

  /// Runs [body], an API call (or a few) that reports its own failures by
  /// throwing [ProcessExit], and returns null if it succeeds.
  ///
  /// With `--json`, a [ProcessExit] is reported as an error envelope carrying
  /// [code] and [message], and its exit code is returned for the caller to
  /// return from `run`. A failed API call ([ApiErrorExit]) adds the server's
  /// message to [message] and reports its error code and details, as
  /// [reportApiError] does. The failure is reported here rather than in the
  /// command runner, so the runner never sees it and doesn't emit a second
  /// envelope. Otherwise the [ProcessExit] is rethrown, and the error the
  /// call already logged stands.
  ///
  /// [body] typically assigns `late final` locals that the caller reads once
  /// this returns null.
  Future<int?> guardApiCall(
    Future<void> Function() body, {
    required JsonErrorCode code,
    required String message,
  }) async {
    try {
      await body();
      return null;
    } on PreconditionFailedExit {
      // A failed precondition reports itself (as precondition_failed); don't
      // relabel it as this call's error.
      rethrow;
    } on ApiErrorExit catch (e) {
      if (!isJsonMode) rethrow;
      return reportApiError(e.error, message: message, code: code);
    } on ProcessExit catch (e) {
      if (!isJsonMode) rethrow;
      emitJsonError(code: code, message: message);
      return e.exitCode;
    }
  }
}

/// {@template shorebird_proxy_command}
/// A command in the Shorebird CLI that proxies to an underlying process.
/// {@endtemplate}
abstract class ShorebirdProxyCommand extends ShorebirdCommand {
  @override
  ArgParser get argParser => ArgParser.allowAnything();
}

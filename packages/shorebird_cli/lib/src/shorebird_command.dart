import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/interactive_mode.dart' as interactive_mode;
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/shorebird_cli_command_runner.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Signature for a function which takes a list of bytes and returns a hash.
typedef HashFunction = String Function(List<int> bytes);

/// Signature for a function which takes a path to a zip file.
typedef UnzipFn = Future<void> Function(String zipFilePath, String outputDir);

/// Signature for a function which builds a [CodePushClient].
typedef CodePushClientBuilder =
    CodePushClient Function({required http.Client httpClient, Uri? hostedUri});

/// Signature for a function which starts a process (e.g. [Process.start]).
typedef StartProcess =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      bool runInShell,
    });

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

  /// Resolves the app ID from `--app-id` or `shorebird.yaml`, validating
  /// preconditions in the process.
  ///
  /// Returns `(appId: <id>, errorCode: null)` on success, or
  /// `(appId: '', errorCode: <code>)` if precondition validation failed.
  Future<({String appId, int? errorCode})> resolveAppId() async {
    final explicitAppId = results[CommonArguments.appIdArg.name] as String?;
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: explicitAppId == null,
      );
    } on PreconditionFailedException catch (error) {
      return (appId: '', errorCode: error.exitCode.code);
    }
    final flavor = results.findOption(
      CommonArguments.flavorArg.name,
      argParser: argParser,
    );
    final appId =
        explicitAppId ??
        shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);
    return (appId: appId, errorCode: null);
  }

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
  }) {
    JsonResult.error(
      code: code,
      message: message,
      hint: hint,
      command: fullCommandName,
    ).write();
  }
}

/// {@template shorebird_proxy_command}
/// A command in the Shorebird CLI that proxies to an underlying process.
/// {@endtemplate}
abstract class ShorebirdProxyCommand extends ShorebirdCommand {
  @override
  ArgParser get argParser => ArgParser.allowAnything();
}

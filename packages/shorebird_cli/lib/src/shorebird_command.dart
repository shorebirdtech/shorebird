import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/shorebird_cli_command_runner.dart';
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

  /// Emits a JSON error envelope to stdout.
  ///
  /// Only call this when [isJsonMode] is true.
  void emitJsonError({
    required String code,
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

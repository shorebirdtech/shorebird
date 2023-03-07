import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_code_push_api_client/shorebird_code_push_api_client.dart';

typedef CodePushClientBuilder = ShorebirdCodePushApiClient Function({
  required String apiKey,
});

typedef StartProcess = Future<Process> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

abstract class ShorebirdCommand extends Command<int> {
  ShorebirdCommand({
    Auth? auth,
    CodePushClientBuilder? buildCodePushClient,
    Logger? logger,
    RunProcess? runProcess,
    StartProcess? startProcess,
  })  : auth = auth ?? Auth(),
        buildCodePushClient =
            buildCodePushClient ?? ShorebirdCodePushApiClient.new,
        logger = logger ?? Logger(),
        runProcess = runProcess ?? Process.run,
        startProcess = startProcess ?? Process.start;

  final Auth auth;
  final CodePushClientBuilder buildCodePushClient;
  final Logger logger;
  final RunProcess runProcess;
  final StartProcess startProcess;

  /// [ArgResults] used for testing purposes only.
  @visibleForTesting
  ArgResults? testArgResults;

  /// [ArgResults] for the current command.
  ArgResults get results => testArgResults ?? argResults!;

  /// [CommandRunner] used for testing purposes only.
  @visibleForTesting
  CommandRunner<int>? testCommandRunner;

  @override
  CommandRunner<int>? get runner => testCommandRunner ?? super.runner;
}

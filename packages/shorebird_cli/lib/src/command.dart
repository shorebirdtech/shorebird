import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Signature for a function which takes a list of bytes and returns a hash.
typedef HashFunction = String Function(List<int> bytes);

typedef CodePushClientBuilder = CodePushClient Function({
  required http.Client httpClient,
  Uri? hostedUri,
});

typedef StartProcess = Future<Process> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

abstract class ShorebirdCommand extends Command<int> {
  ShorebirdCommand({
    required this.logger,
    Auth? auth,
    CodePushClientBuilder? buildCodePushClient,
    RunProcess? runProcess,
    StartProcess? startProcess,
    ShorebirdFlutterValidator? flutterValidator,
  })  : auth = auth ?? Auth(),
        buildCodePushClient = buildCodePushClient ?? CodePushClient.new,
        runProcess = runProcess ?? ShorebirdProcess.run,
        startProcess = startProcess ?? ShorebirdProcess.start {
    this.flutterValidator = flutterValidator ??
        ShorebirdFlutterValidator(runProcess: this.runProcess);
  }

  final Auth auth;
  final CodePushClientBuilder buildCodePushClient;
  final Logger logger;
  final RunProcess runProcess;
  final StartProcess startProcess;
  late final ShorebirdFlutterValidator flutterValidator;

  /// [ArgResults] used for testing purposes only.
  @visibleForTesting
  ArgResults? testArgResults;

  /// [ArgResults] for the current command.
  ArgResults get results => testArgResults ?? argResults!;
}

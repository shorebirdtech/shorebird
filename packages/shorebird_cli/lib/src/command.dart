import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/cache.dart';
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

List<Validator> _defaultValidators({required RunProcess runProcess}) {
  return [
    ShorebirdFlutterValidator(runProcess: runProcess),
    AndroidInternetPermissionValidator(),
  ];
}

abstract class ShorebirdCommand extends Command<int> {
  ShorebirdCommand({
    required this.logger,
    Auth? auth,
    Cache? cache,
    CodePushClientBuilder? buildCodePushClient,
    List<Validator>? validators,
    ShorebirdProcess? process,
  })  : auth = auth ?? Auth(),
        cache = cache ?? Cache(),
        buildCodePushClient = buildCodePushClient ?? CodePushClient.new,
        process = process ?? ShorebirdProcess() {
    this.validators =
        validators ?? _defaultValidators(runProcess: this.process.run);
  }

  final Auth auth;
  final Cache cache;
  final CodePushClientBuilder buildCodePushClient;
  final Logger logger;
  final ShorebirdProcess process;

  /// Checks that the Shorebird install and project are in a good state.
  late List<Validator> validators;

  /// [ArgResults] used for testing purposes only.
  @visibleForTesting
  ArgResults? testArgResults;

  /// [ArgResults] for the current command.
  ArgResults get results => testArgResults ?? argResults!;
}

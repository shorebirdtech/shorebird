import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Signature for a function which takes a list of bytes and returns a hash.
typedef HashFunction = String Function(List<int> bytes);

/// Signature for a function which takes a path to a zip file.
typedef UnzipFn = Future<void> Function(String zipFilePath, String outputDir);

typedef CodePushClientBuilder = CodePushClient Function({
  required http.Client httpClient,
  Uri? hostedUri,
});

typedef StartProcess = Future<Process> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

List<Validator> _defaultValidators() => [
      AndroidInternetPermissionValidator(),
    ];

abstract class ShorebirdCommand extends Command<int> {
  ShorebirdCommand({
    CodePushClientBuilder? buildCodePushClient,
    List<Validator>? validators, // For mocking.
  })  : buildCodePushClient = buildCodePushClient ?? CodePushClient.new,
        validators = validators ?? _defaultValidators();

  final CodePushClientBuilder buildCodePushClient;

  // We don't currently have a test involving both a CommandRunner
  // and a Command, so we can't test this getter.
  // coverage:ignore-start
  @override
  ShorebirdCliCommandRunner? get runner =>
      super.runner as ShorebirdCliCommandRunner?;
  // coverage:ignore-end

  /// Checks that the Shorebird install and project are in a good state.
  late List<Validator> validators;

  /// [ArgResults] used for testing purposes only.
  @visibleForTesting
  ArgResults? testArgResults;

  /// [ArgResults] for the current command.
  ArgResults get results => testArgResults ?? argResults!;
}

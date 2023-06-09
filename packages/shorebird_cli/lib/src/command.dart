import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:checked_yaml/checked_yaml.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_runner.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
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
    Auth? auth,
    Cache? cache,
    CodePushClientBuilder? buildCodePushClient,
    CodePushClientWrapper? codePushClientWrapper,
    List<Validator>? validators, // For mocking.
  })  : cache = cache ?? Cache(),
        buildCodePushClient = buildCodePushClient ?? CodePushClient.new,
        validators = validators ?? _defaultValidators() {
    this.auth = auth ?? Auth();
    this.codePushClientWrapper = codePushClientWrapper ??
        CodePushClientWrapper(
          codePushClient: CodePushClient(
            httpClient: this.auth.client,
            hostedUri: hostedUri,
          ),
        );
  }

  late final Auth auth;
  final Cache cache;
  final CodePushClientBuilder buildCodePushClient;
  late final CodePushClientWrapper codePushClientWrapper;

  // We don't currently have a test involving both a CommandRunner
  // and a Command, so we can't test this getter.
  // coverage:ignore-start
  @override
  ShorebirdCliCommandRunner? get runner =>
      super.runner as ShorebirdCliCommandRunner?;
  // coverage:ignore-end

  /// [ShorebirdProcess] used for testing purposes only.
  @visibleForTesting
  ShorebirdProcess? testProcess;

  // If you hit a late initialization error here, it's because you're either
  // using process before runCommand has been called, or you're in a test
  // and should set testProcess instead.
  ShorebirdProcess get process => testProcess ?? runner!.process;

  /// [EngineConfig] used for testing purposes only.
  @visibleForTesting
  EngineConfig? testEngineConfig;

  // If you hit a late initialization error here, it's because you're either
  // using engineConfig before runCommand has been called, or you're in a test
  // and should set testEngineConfig instead.
  EngineConfig get engineConfig => testEngineConfig ?? process.engineConfig;

  /// Checks that the Shorebird install and project are in a good state.
  late List<Validator> validators;

  /// [ArgResults] used for testing purposes only.
  @visibleForTesting
  ArgResults? testArgResults;

  /// [ArgResults] for the current command.
  ArgResults get results => testArgResults ?? argResults!;

  File getShorebirdYamlFile() {
    return File(p.join(Directory.current.path, 'shorebird.yaml'));
  }

  ShorebirdYaml? getShorebirdYaml() {
    final file = getShorebirdYamlFile();
    if (!file.existsSync()) return null;
    final yaml = file.readAsStringSync();
    return checkedYamlDecode(yaml, (m) => ShorebirdYaml.fromJson(m!));
  }

  Pubspec? getPubspecYaml() {
    final file = File(p.join(Directory.current.path, 'pubspec.yaml'));
    if (!file.existsSync()) return null;
    final yaml = file.readAsStringSync();
    return Pubspec.parse(yaml);
  }

  Uri? get hostedUri {
    // TODO(bryanoltman): maybe look for an environment variable instead of
    // reading shorebird.yaml?
    try {
      final baseUrl = getShorebirdYaml()?.baseUrl;
      return baseUrl == null ? null : Uri.tryParse(baseUrl);
    } catch (_) {
      return null;
    }
  }
}

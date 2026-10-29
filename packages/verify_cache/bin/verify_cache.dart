import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:verify_cache/verify_cache.dart';

const _usage =
    'usage: verify_cache [--force] [--tool <name>]... [--input <path>]... '
    '[--dart-package <path>] [--cache-dir <dir>] -- <command> [<arg>...]\n'
    '       verify_cache --lookup [--tool <name>]... [--input <path>]... '
    '[--dart-package <path>]... [--cache-dir <dir>] -- <command> [<arg>...]';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser(allowTrailingOptions: false)
    ..addFlag(
      'force',
      negatable: false,
      help: 'Run the command even when its inputs already passed.',
    )
    ..addFlag(
      'lookup',
      negatable: false,
      help:
          'Run nothing, and print as one JSON list each --dart-package with '
          'a recorded pass, each with `{}` in the command replaced by it. '
          'One process answers for every package, where a run for each '
          'starts dart once per package.',
    )
    ..addMultiOption(
      'tool',
      help: 'A tool whose `--version` is part of the key. Repeatable.',
    )
    ..addMultiOption(
      'input',
      help:
          'A path, relative to the checkout root, whose working-tree hash is '
          'part of the key. Repeatable. With neither this nor '
          '--dart-package, the key covers the whole working tree.',
    )
    ..addMultiOption(
      'dart-package',
      splitCommas: false,
      help:
          'A Dart package, relative to the checkout root, whose dependency '
          'closure and workspace files are inputs. Repeatable with --lookup.',
    )
    ..addOption(
      'cache-dir',
      help:
          r'Where passes are kept. Defaults to $VERIFY_CACHE_DIR, then '
          r'$XDG_CACHE_HOME/shorebird-verify-cache, then '
          '~/.cache/shorebird-verify-cache.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr
      ..writeln('error: ${e.message}')
      ..writeln(_usage);
    exit(2);
  }
  if (results.flag('help')) {
    stdout
      ..writeln(_usage)
      ..writeln(parser.usage);
    return;
  }
  if (results.rest.isEmpty) {
    stderr
      ..writeln('error: no command given')
      ..writeln(_usage);
    exit(2);
  }

  final inputs = [...results.multiOption('input')];
  final packages = results.multiOption('dart-package');
  final lookup = results.flag('lookup');
  if (packages.length > 1 && !lookup) {
    stderr
      ..writeln('error: more than one --dart-package needs --lookup')
      ..writeln(_usage);
    exit(2);
  }
  final cacheDir = results.option('cache-dir');
  final cacheDirectory = cacheDir != null
      ? Directory(cacheDir)
      : defaultCacheDirectory(Platform.environment);

  // Each package's inputs, with the ones every package shares.
  final packageInputs = <String, List<String>>{};
  if (packages.isNotEmpty) {
    final checkout = await GitTree.find(Directory.current.path);
    if (checkout == null) {
      stderr.writeln('error: --dart-package needs a git checkout');
      exit(2);
    }
    try {
      for (final package in packages) {
        packageInputs[package] = [
          ...inputs,
          ...dartPackageInputs(checkout.root, package),
        ];
      }
    } on FormatException catch (e) {
      stderr.writeln('error: ${e.message}');
      exit(2);
    }
  }

  if (lookup) {
    if (packages.isEmpty) {
      stderr
        ..writeln('error: --lookup needs at least one --dart-package')
        ..writeln(_usage);
      exit(2);
    }
    final passed = await lookupPasses(
      commands: [
        for (final package in packages)
          (
            command: results.rest
                .map((argument) => argument == '{}' ? package : argument)
                .toList(),
            inputs: packageInputs[package]!,
          ),
      ],
      workingDirectory: Directory.current.path,
      cacheDirectory: cacheDirectory,
      tools: results.multiOption('tool'),
    );
    // Without a cache to read, nothing has passed, so a caller runs each.
    stdout.writeln(
      jsonEncode([
        for (final (i, package) in packages.indexed)
          if (passed?[i] ?? false) package,
      ]),
    );
    return;
  }
  if (packages.isNotEmpty) {
    inputs
      ..clear()
      ..addAll(packageInputs[packages.single]!);
  }

  final int? slots;
  try {
    slots = slotsFromEnvironment(Platform.environment);
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}');
    exit(2);
  }

  exitCode = await runCached(
    command: results.rest,
    workingDirectory: Directory.current.path,
    cacheDirectory: cacheDirectory,
    inputs: inputs.isEmpty ? const ['.'] : inputs,
    tools: results.multiOption('tool'),
    force: results.flag('force'),
    slots: slots,
    log: (message) => stdout.writeln('verify_cache: $message'),
    // A command run while holding a slot tells any verify_cache inside it
    // that its slot is taken care of.
    run: (command, workingDirectory) => runInheritingStdio(
      command,
      workingDirectory,
      environment: {if (slots != null) slotHeldVariable: '1'},
    ),
  );
}

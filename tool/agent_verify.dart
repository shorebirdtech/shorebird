// Runs the checks CI runs on each workspace package, through
// packages/verify_cache, so a package whose inputs already passed, in any
// worktree, is not checked again. See tool/agent-verify.sh, which runs this.
//
// It imports only dart: libraries, so it starts without the workspace
// resolved, and resolves it itself.
import 'dart:convert';
import 'dart:io';

/// This script, relative to the root. It names the inner command, and is an
/// input of every package's key, so a change to how a package is checked
/// checks it again.
const _self = 'tool/agent_verify.dart';

/// Packages whose tests need a service a laptop does not run. CI starts it
/// (`needs_redis` in .github/workflows/shorebird_ci.yaml); here they get
/// format and analyze only.
const _testsNeedServices = {'packages/redis_client': 'a Redis server'};

const _usage = 'usage: tool/agent-verify.sh [--plan] [--force]';

Future<void> main(List<String> arguments) async {
  if (arguments case ['--package', final package]) {
    exit(await _checkPackage(package));
  }
  final rest = [...arguments];
  final force = rest.remove('--force');
  final plan = rest.remove('--plan');
  if (rest.isNotEmpty) {
    stderr
      ..writeln('error: agent-verify takes no paths, got ${rest.first}')
      ..writeln(_usage);
    exit(2);
  }

  final packages = _workspacePackages();
  if (plan) {
    for (final package in packages) {
      stdout.writeln('dart: $package');
    }
    return;
  }

  // `dart run verify_cache` needs the workspace resolved, and a fresh
  // worktree has not been.
  final resolve = await Process.run('dart', ['pub', 'get']);
  if (resolve.exitCode != 0) {
    stderr
      ..write(resolve.stdout)
      ..write(resolve.stderr)
      ..writeln('error: dart pub get failed, so nothing was verified');
    exit(3);
  }

  final passed = force ? const <String>{} : await _passed(packages);
  final failures = <String>[];
  for (final package in packages) {
    if (passed.contains(package)) {
      stdout.writeln('$package: already verified');
      continue;
    }
    stdout.writeln('$package: checking');
    final process = await Process.start('dart', [
      'run',
      'verify_cache',
      '--dart-package',
      package,
      ..._keyOptions,
      if (force) '--force',
      '--',
      ..._check(package),
    ], mode: ProcessStartMode.inheritStdio);
    if (await process.exitCode != 0) failures.add(package);
  }

  if (failures.isEmpty) {
    stdout.writeln('agent-verify: all ${packages.length} packages passed');
    return;
  }
  stdout.writeln('agent-verify: failed: ${failures.join(', ')}');
  exit(1);
}

const _keyOptions = ['--input', _self, '--tool', 'dart'];

List<String> _check(String package) => ['dart', _self, '--package', package];

/// Which of [packages] already passed, asked of verify_cache in one process
/// rather than a `dart run` per package. Empty when the lookup fails, so each
/// package's own run finds its pass.
Future<Set<String>> _passed(List<String> packages) async {
  final result = await Process.run('dart', [
    'run',
    'verify_cache',
    '--lookup',
    for (final package in packages) ...['--dart-package', package],
    ..._keyOptions,
    '--',
    ..._check('{}'),
  ]);
  if (result.exitCode != 0) return const {};
  // The list is the last line; `dart run` may say it built the tool first.
  final last = (result.stdout as String).trim().split('\n').last;
  try {
    final decoded = jsonDecode(last);
    if (decoded is List) return {...decoded.whereType<String>()};
  } on FormatException {
    // Not the list, so nothing is taken as passed.
  }
  return const {};
}

/// Format, analyze and test of [package], as
/// .github/workflows/_shorebird_ci_dart.yaml runs them, less coverage.
Future<int> _checkPackage(String package) async {
  final failed = <String>[];
  Future<void> check(String what, List<String> arguments) async {
    stdout.writeln('$package: $what');
    final process = await Process.start(
      'dart',
      arguments,
      workingDirectory: package,
      mode: ProcessStartMode.inheritStdio,
    );
    if (await process.exitCode != 0) failed.add(what);
  }

  // `-o none` because dart format otherwise writes in place, and the tree it
  // reformatted would then pass.
  await check('format', ['format', '-o', 'none', '--set-exit-if-changed', '.']);
  await check('analyze', ['analyze', '--fatal-warnings', '.']);
  final service = _testsNeedServices[package];
  if (service != null) {
    stdout.writeln('$package: tests need $service, which CI starts; skipped');
  } else if (Directory('$package/test').existsSync()) {
    await check('test', ['test', '-j', '4']);
  }
  if (failed.isEmpty) return 0;
  stdout.writeln('$package: failed ${failed.join(', ')}');
  return 1;
}

/// The workspace list in the root pubspec, which is the set CI checks. Read
/// by hand, because package:yaml is not resolved before `dart pub get`.
List<String> _workspacePackages() {
  final lines = File('pubspec.yaml').readAsLinesSync();
  final start = lines.indexOf('workspace:');
  if (start < 0) return const [];
  return [
    for (final line
        in lines
            .skip(start + 1)
            .takeWhile(
              (line) => line.startsWith('  - '),
            ))
      line.substring(4).trim(),
  ];
}

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:verify_cache/src/cache_key.dart';
import 'package:verify_cache/src/git_tree.dart';
import 'package:verify_cache/src/key_lock.dart';
import 'package:verify_cache/src/result_store.dart';
import 'package:verify_cache/src/run_slot.dart';

/// Runs a command in a directory and completes with its exit code.
typedef CommandRunner =
    Future<int> Function(List<String> command, String workingDirectory);

/// Runs [command] with this process's stdin, stdout and stderr, and its
/// environment plus [environment].
Future<int> runInheritingStdio(
  List<String> command,
  String workingDirectory, {
  Map<String, String> environment = const {},
}) async {
  final process = await Process.start(
    command.first,
    command.skip(1).toList(),
    workingDirectory: workingDirectory,
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  return await process.exitCode;
}

/// Runs [command] in [workingDirectory] unless a pass over the same inputs
/// is already recorded in [cacheDirectory], and completes with the exit code
/// a full run would give.
///
/// The inputs are the working tree's hash of each of [inputs], [command],
/// the directory, the `--version` of each of [tools], and the platform. See
/// [CacheKey]. [inputs] are relative to the checkout root, and the default,
/// `.`, is the whole working tree.
///
/// - A working tree is hashed as it is on disk, uncommitted and untracked
///   files included and ignored files not. See [GitTree.workingTreeHash].
/// - Only an exit code of 0 is recorded. A failure may be a flake, and the
///   next run should get to try again.
/// - A pass is recorded only if [inputs] hash the same when the command
///   exits, so a command that writes into them, or an edit made while it
///   runs, cannot record a pass over files it did not check.
/// - [force] runs the command even when a pass is recorded, and records the
///   new pass.
/// - Runs over the same inputs hold a [KeyLock] while they run, so the
///   second waits for the first and then takes its pass.
/// - With [slots], a run that has to check something first takes one of
///   that many machine-wide [RunSlot]s, waiting for one if all are held. A
///   recorded pass is answered without one.
Future<int> runCached({
  required List<String> command,
  required String workingDirectory,
  required Directory cacheDirectory,
  List<String> inputs = const ['.'],
  List<String> tools = const [],
  bool force = false,
  int? slots,
  void Function(String message) log = print,
  CommandRunner run = runInheritingStdio,
}) async {
  final checkout = await GitTree.find(workingDirectory);
  if (checkout == null) {
    log('not in a git checkout, so the result cache is not used');
    return await run(command, workingDirectory);
  }
  Future<Map<String, String>?> hashInputs() async {
    final tree = await checkout.workingTreeHash();
    return tree == null ? null : await checkout.hashesIn(tree, inputs);
  }

  final hashes = await hashInputs();
  if (hashes == null) {
    log('git could not hash the working tree, so the result cache is not used');
    return await run(command, workingDirectory);
  }
  for (final MapEntry(key: path, value: hash) in hashes.entries) {
    // A path a pubspec names that is gone, perhaps renamed, still gives a
    // key, so it is said here rather than left to look covered.
    if (hash == 'absent') log('input $path does not exist');
  }

  final key = CacheKey(
    inputs: hashes,
    directory: _relativeDirectory(checkout, workingDirectory),
    command: command,
    tools: await _toolVersions(tools),
    platform: currentPlatform(),
  );
  final digest = key.digest;
  final store = ResultStore(cacheDirectory);

  bool reportHit() {
    if (force) return false;
    final entry = store.lookup(digest);
    if (entry == null) return false;
    // One line, since a caller may check dozens of packages this way. The
    // entry, with every input, is in the store under [digest].
    final when = switch (jsonDecode(entry)) {
      {'passed': final String passed, 'checkout': final String checkout} =>
        ' (passed $passed in $checkout)',
      _ => '',
    };
    log('already verified$when, skipping the run (--force runs it anyway)');
    return true;
  }

  if (reportHit()) return 0;
  if (force) log('--force, running without consulting the cache');

  final lock = await KeyLock.acquire(
    cacheDirectory,
    digest,
    onWait: () => log('another run is verifying these inputs, waiting'),
  );
  try {
    // The run that held the lock may have just passed these inputs.
    if (reportHit()) return 0;
    final slot = slots == null
        ? null
        : await RunSlot.acquire(
            cacheDirectory,
            slots,
            onWait: () => log(
              '$slots runs are already checking on this machine, waiting '
              'for one to finish (VERIFY_CACHE_SLOTS sets how many)',
            ),
          );
    try {
      if (!force) log('no recorded pass for these inputs, running');

      final started = DateTime.now();
      final exitCode = await run(command, workingDirectory);
      if (exitCode != 0) return exitCode;

      final after = await hashInputs();
      if (after == null || !_sameHashes(after, hashes)) {
        log('the inputs changed during the run, so this pass is not recorded');
        return 0;
      }
      store.record(
        digest,
        const JsonEncoder.withIndent('  ').convert({
          'passed': started.toUtc().toIso8601String(),
          'seconds': DateTime.now().difference(started).inSeconds,
          'checkout': checkout.root,
          'inputs': key.toJson(),
        }),
      );
      log('recorded this pass as $digest');
      return 0;
    } finally {
      await slot?.release();
    }
  } finally {
    await lock.release();
  }
}

/// A command and the inputs its pass is keyed on, as [runCached] takes them.
typedef CachedCommand = ({List<String> command, List<String> inputs});

/// Whether [runCached] would find a recorded pass for each of [commands], in
/// order, run in [workingDirectory] with [tools]. Null when [workingDirectory]
/// is in no checkout or git cannot hash its working tree, which is when
/// [runCached] uses no cache either.
///
/// It runs nothing and takes no lock or slot. The working tree is hashed once
/// and each tool's version read once for all of [commands], so asking about
/// dozens costs about what asking about one does, where a [runCached] for
/// each would hash the tree and start every tool once per command. A command
/// without a pass may still have one by the time it is run, which
/// [runCached] then finds.
Future<List<bool>?> lookupPasses({
  required List<CachedCommand> commands,
  required String workingDirectory,
  required Directory cacheDirectory,
  List<String> tools = const [],
}) async {
  final checkout = await GitTree.find(workingDirectory);
  if (checkout == null) return null;
  final tree = await checkout.workingTreeHash();
  if (tree == null) return null;
  final hashes = await checkout.hashesIn(tree, [
    ...{for (final command in commands) ...command.inputs},
  ]);
  if (hashes == null) return null;

  final directory = _relativeDirectory(checkout, workingDirectory);
  final versions = await _toolVersions(tools);
  final platform = currentPlatform();
  final store = ResultStore(cacheDirectory);
  return [
    for (final (:command, :inputs) in commands)
      store.lookup(
            CacheKey(
              inputs: {for (final path in inputs) path: hashes[path]!},
              directory: directory,
              command: command,
              tools: versions,
              platform: platform,
            ).digest,
          ) !=
          null,
  ];
}

String _relativeDirectory(GitTree checkout, String workingDirectory) =>
    p.relative(
      Directory(workingDirectory).resolveSymbolicLinksSync(),
      from: checkout.root,
    );

Future<Map<String, String>> _toolVersions(List<String> tools) async => {
  for (final tool in tools) tool: await toolVersion(tool),
};

bool _sameHashes(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.keys.every((key) => a[key] == b[key]);

/// Where the cache lives when no directory is given: `$VERIFY_CACHE_DIR`,
/// else `$XDG_CACHE_HOME/shorebird-verify-cache`, else
/// `$HOME/.cache/shorebird-verify-cache`. Outside every checkout, so all of
/// them share it.
Directory defaultCacheDirectory(Map<String, String> environment) {
  final explicit = environment['VERIFY_CACHE_DIR'];
  if (explicit != null && explicit.isNotEmpty) return Directory(explicit);
  final xdg = environment['XDG_CACHE_HOME'];
  final base = xdg != null && xdg.isNotEmpty
      ? xdg
      : p.join(environment['HOME'] ?? '.', '.cache');
  return Directory(p.join(base, 'shorebird-verify-cache'));
}

import 'dart:io';

import 'package:path/path.dart' as p;

/// The git checkout a command runs in.
class GitTree {
  /// A checkout whose top-level directory is [root].
  GitTree(this.root);

  /// The top-level directory of the checkout, with symlinks resolved.
  final String root;

  /// The checkout containing [directory], or null when it is in none.
  static Future<GitTree?> find(String directory) async {
    final result = await Process.run('git', [
      'rev-parse',
      '--show-toplevel',
    ], workingDirectory: directory);
    if (result.exitCode != 0) return null;
    return GitTree((result.stdout as String).trim());
  }

  /// The hash of the tree the working tree holds, or null when git cannot
  /// write one.
  ///
  /// That is every file as it is on disk: committed, staged, modified and
  /// untracked alike, and a deleted file is absent. Ignored files do not
  /// count: they are build outputs and dependency installs, which the tree's
  /// lockfiles describe.
  ///
  /// It is written through a copy of the index, so the checkout's own index
  /// is never touched, and the copy's cached stat data means only files that
  /// changed since the last `git add` or `git status` are read.
  Future<String?> workingTreeHash() async {
    final indexPath = await _git(['rev-parse', '--git-path', 'index']);
    if (indexPath == null) return null;
    final index = File(p.join(root, indexPath));
    final temp = Directory.systemTemp.createTempSync('verify_cache_index.');
    try {
      final copy = p.join(temp.path, 'index');
      if (index.existsSync()) index.copySync(copy);
      final environment = {'GIT_INDEX_FILE': copy};
      if (await _git(['add', '-A'], environment: environment) == null) {
        return null;
      }
      return await _git(['write-tree'], environment: environment);
    } finally {
      temp.deleteSync(recursive: true);
    }
  }

  /// The hash of each of [paths] in [tree], by path, or null when git cannot
  /// read [tree].
  ///
  /// [paths] are relative to [root]. `.` is [tree] itself, and a path [tree]
  /// does not hold is `absent`, so creating it changes the result.
  Future<Map<String, String>?> hashesIn(String tree, List<String> paths) async {
    final named = [
      for (final path in paths)
        if (p.normalize(path) != '.') p.normalize(path),
    ];
    final found = <String, String>{};
    if (named.isNotEmpty) {
      final listing = await _git(['ls-tree', '-z', tree, '--', ...named]);
      if (listing == null) return null;
      for (final entry in listing.split('\x00')) {
        if (entry.isEmpty) continue;
        // `<mode> <type> <hash>\t<path>`
        final tab = entry.indexOf('\t');
        found[entry.substring(tab + 1)] = entry.substring(0, tab).split(' ')[2];
      }
    }
    return {
      for (final path in paths)
        path: p.normalize(path) == '.'
            ? tree
            : found[p.normalize(path)] ?? 'absent',
    };
  }

  Future<String?> _git(
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: root,
      environment: environment,
    );
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A fresh directory, deleted after the test, with symlinks resolved so it
/// compares equal to what git reports.
Directory tempDir() {
  final dir = Directory.systemTemp.createTempSync('verify_cache_test.');
  addTearDown(() => dir.deleteSync(recursive: true));
  return Directory(dir.resolveSymbolicLinksSync());
}

/// Runs git in [dir] and returns its trimmed stdout, failing on a nonzero
/// exit.
String git(Directory dir, List<String> args) {
  final result = Process.runSync('git', [
    '-c',
    'user.name=test',
    '-c',
    'user.email=test@example.com',
    ...args,
  ], workingDirectory: dir.path);
  if (result.exitCode != 0) {
    fail('git ${args.join(' ')} failed: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

/// A git checkout holding one committed file, `a.txt`.
Directory gitRepo() {
  final dir = Directory(p.join(tempDir().path, 'repo'))..createSync();
  git(dir, ['init', '-q']);
  File(p.join(dir.path, 'a.txt')).writeAsStringSync('a\n');
  git(dir, ['add', '-A']);
  git(dir, ['commit', '-qm', 'init']);
  return dir;
}

/// A process holding the lock on [digest] under [cacheDir], started and
/// holding by the time this completes. Killed after the test.
Future<Process> holdLock(Directory cacheDir, String digest) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    p.join('test', 'fixtures', 'hold_lock.dart'),
    cacheDir.path,
    digest,
  ]);
  addTearDown(process.kill);
  final line = await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first;
  expect(line, 'held');
  return process;
}

/// A process holding one of [count] slots under [cacheDir], started and
/// holding by the time this completes. Killed after the test.
Future<Process> holdSlot(Directory cacheDir, int count) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    p.join('test', 'fixtures', 'hold_slot.dart'),
    cacheDir.path,
    '$count',
  ]);
  addTearDown(process.kill);
  final line = await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first;
  expect(line, 'held');
  return process;
}

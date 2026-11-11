import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _compiledFixtures = <String, Future<String>>{};
Future<Directory>? _fixtureDir;

/// A temporary directory for the current test suite's compiled fixtures.
///
/// Uses [Isolate.addOnExitListener] rather than [tearDownAll] because
/// [holdLock] and [holdSlot] are called from inside running tests, after
/// `package:test` has finished building the suite and rejects [tearDownAll].
Future<Directory> _createSuiteTempDir() async {
  final dir = Directory.systemTemp.createTempSync('verify_cache_fixture.');
  final ready = ReceivePort();
  await Isolate.spawn(_deleteOnExit, (ready.sendPort, dir.path));
  Isolate.current.addOnExitListener(await ready.first as SendPort);
  ready.close();
  return dir;
}

Future<void> _deleteOnExit((SendPort, String) args) async {
  final (ready, path) = args;
  final onExit = ReceivePort();
  ready.send(onExit.sendPort);
  await onExit.first;
  onExit.close();
  try {
    Directory(path).deleteSync(recursive: true);
  } on FileSystemException {
    // Best effort if already removed.
  }
}

Future<String> _compileFixture(String name) =>
    _compiledFixtures.putIfAbsent(name, () async {
      final dir = await (_fixtureDir ??= _createSuiteTempDir());
      final output = p.join(dir.path, '$name.dill');
      final result = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        p.join('test', 'fixtures', name),
        '-o',
        output,
      ]);
      if (result.exitCode != 0) {
        fail('dart compile kernel $name failed: ${result.stderr}');
      }
      return output;
    });

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
  final fixture = await _compileFixture('hold_lock.dart');
  final process = await Process.start(Platform.resolvedExecutable, [
    fixture,
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

/// Starts a process that acquires one of [count] slots under [cacheDir] and
/// holds it until killed. Killed after the test.
Future<Process> startHoldSlot(Directory cacheDir, int count) async {
  final fixture = await _compileFixture('hold_slot.dart');
  final process = await Process.start(Platform.resolvedExecutable, [
    fixture,
    cacheDir.path,
    '$count',
  ]);
  addTearDown(process.kill);
  return process;
}

/// A process holding one of [count] slots under [cacheDir], started and
/// holding by the time this completes. Killed after the test.
Future<Process> holdSlot(Directory cacheDir, int count) async {
  final process = await startHoldSlot(cacheDir, count);
  final line = await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first;
  expect(line, 'held');
  return process;
}

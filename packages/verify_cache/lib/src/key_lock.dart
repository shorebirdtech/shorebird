import 'dart:io';

import 'package:path/path.dart' as p;

/// An exclusive lock on one key, so concurrent runs over the same inputs
/// wait for a single run instead of each doing the work.
///
/// The lock is the operating system's, on a file under `locks/`. The kernel
/// drops it when its holder exits, however it exits, so a killed run never
/// leaves a lock behind for anyone to detect or clear.
///
/// The lock only saves work. Whether a pass is trusted rests on its key, so
/// a lock that failed to exclude would cost a duplicate run and nothing else.
class KeyLock {
  KeyLock._(this._file);

  final RandomAccessFile _file;

  /// Takes the lock on [digest] under [directory], waiting for any other
  /// holder. Calls [onWait] once before waiting, if it has to wait.
  ///
  /// Lock files are never deleted. Deleting one would let a waiter go on
  /// holding a lock on the deleted file while a newcomer locks a fresh one
  /// at the same path, and both would run.
  static Future<KeyLock> acquire(
    Directory directory,
    String digest, {
    void Function()? onWait,
  }) async {
    final path = p.join(directory.path, 'locks', '$digest.lock');
    await Directory(p.dirname(path)).create(recursive: true);
    // Append, so opening never truncates a file another process holds.
    final file = await File(path).open(mode: FileMode.append);
    try {
      // The default mode: exclusive, and throwing rather than waiting.
      await file.lock();
    } on FileSystemException {
      onWait?.call();
      await file.lock(FileLock.blockingExclusive);
    }
    return KeyLock._(file);
  }

  /// Gives the lock up.
  Future<void> release() async {
    await _file.unlock();
    await _file.close();
  }
}

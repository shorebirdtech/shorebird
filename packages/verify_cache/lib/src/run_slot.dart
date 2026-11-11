import 'dart:io';

import 'package:path/path.dart' as p;

/// One of a fixed number of machine-wide slots, so at most that many runs
/// check something at once and the rest queue.
///
/// Runs that overlap compete for the same cores and finish no sooner than
/// they would one after another: four agent-verify runs at once took three
/// to four times as long each as one alone, and the overload timed tests
/// out. A slot turns that into a queue.
///
/// Like a `KeyLock`, a slot is the operating system's lock on a file, under
/// `slots/`, so the kernel drops it when its holder exits.
class RunSlot {
  RunSlot._(this._file, this._path);

  final RandomAccessFile _file;
  final String _path;

  /// Paths locked by this process, since an OS file lock never excludes the
  /// process that already holds it.
  static final _locked = <String>{};
  static var _nextTicket = 0;

  /// How long a waiting run sleeps before it tries every slot again.
  static const retryInterval = Duration(seconds: 1);

  /// Takes one of [count] slots under [directory], waiting until one is
  /// free. Waiters are served in arrival order. Calls [onWait] once before
  /// waiting, if it has to wait.
  static Future<RunSlot> acquire(
    Directory directory,
    int count, {
    void Function()? onWait,
  }) async {
    if (count < 1) throw ArgumentError.value(count, 'count', 'must be >= 1');
    final slots = Directory(p.join(directory.path, 'slots'));
    final queue = Directory(p.join(slots.path, 'queue'));
    await queue.create(recursive: true);

    final ticketName =
        '${DateTime.now().microsecondsSinceEpoch.toString().padLeft(20, '0')}'
        '-$pid-${(_nextTicket++).toString().padLeft(8, '0')}';
    final ticketFile = File(p.join(queue.path, ticketName));
    // Created and locked in a temporary path before entering queue/, so no
    // concurrent waiter ever sees an unlocked ticket in queue/.
    final stagingFile = File(p.join(slots.path, '.$ticketName.tmp'));
    final ticket = stagingFile.openSync(mode: FileMode.append)..lockSync();
    stagingFile.renameSync(ticketFile.path);
    _locked.add(ticketFile.path);

    try {
      var waited = false;
      while (true) {
        if (!_hasWaiterAhead(queue, ticketName)) {
          for (var i = 0; i < count; i++) {
            final slotFile = File(p.join(slots.path, '$i.lock'));
            final locked = await _tryLock(slotFile);
            if (locked != null) return RunSlot._(locked, slotFile.path);
          }
        }
        if (!waited) {
          waited = true;
          onWait?.call();
        }
        await Future<void>.delayed(retryInterval);
      }
    } finally {
      _locked.remove(ticketFile.path);
      ticketFile.deleteSync();
      ticket
        ..unlockSync()
        ..closeSync();
    }
  }

  static bool _hasWaiterAhead(Directory queue, String ticketName) {
    final entries = queue.listSync().whereType<File>().toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    for (final file in entries) {
      if (p.basename(file.path).compareTo(ticketName) >= 0) break;
      if (_locked.contains(file.path)) return true;
      RandomAccessFile? stale;
      try {
        stale = file.openSync()..lockSync(FileLock.shared);
        file.deleteSync();
        stale.unlockSync();
      } on FileSystemException {
        if (file.existsSync()) return true;
      } finally {
        stale?.closeSync();
      }
    }
    return false;
  }

  static Future<RandomAccessFile?> _tryLock(File file) async {
    if (!_locked.add(file.path)) return null;
    // Append, so opening never truncates a file another process holds.
    final opened = await file.open(mode: FileMode.append);
    try {
      // The default mode: exclusive, and throwing rather than waiting.
      await opened.lock();
      return opened;
    } on FileSystemException {
      _locked.remove(file.path);
      await opened.close();
      return null;
    }
  }

  static Future<void> _unlock(RandomAccessFile file, String path) async {
    _locked.remove(path);
    await file.unlock();
    await file.close();
  }

  /// Gives the slot up.
  Future<void> release() async => _unlock(_file, _path);
}

/// How many runs check at once on one machine when `VERIFY_CACHE_SLOTS` is
/// unset.
const defaultSlots = 4;

/// Set in the environment of a command run while holding a slot, so a
/// verify_cache nested inside it (agent-verify checks each package through
/// one) runs under its parent's slot. Taking a second would deadlock once
/// every slot is held by a parent.
const slotHeldVariable = 'VERIFY_CACHE_SLOT_HELD';

/// The number of slots to take one of, from [environment]: none (`null`)
/// inside a run that already holds one ([slotHeldVariable] set) or when
/// `VERIFY_CACHE_SLOTS` is `0`, else `VERIFY_CACHE_SLOTS`, else
/// [defaultSlots].
///
/// Throws a [FormatException] when `VERIFY_CACHE_SLOTS` is not a whole
/// number of at least 0.
int? slotsFromEnvironment(Map<String, String> environment) {
  if (environment[slotHeldVariable]?.isNotEmpty ?? false) return null;
  final value = environment['VERIFY_CACHE_SLOTS'];
  if (value == null || value.isEmpty) return defaultSlots;
  final slots = int.tryParse(value);
  if (slots == null || slots < 0) {
    throw FormatException(
      'VERIFY_CACHE_SLOTS must be a whole number, 0 for no limit: $value',
    );
  }
  return slots == 0 ? null : slots;
}

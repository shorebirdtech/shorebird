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
  RunSlot._(this._file);

  final RandomAccessFile _file;

  /// How long a waiting run sleeps before it tries every slot again.
  static const retryInterval = Duration(seconds: 1);

  /// Takes one of [count] slots under [directory], waiting until one is
  /// free. Calls [onWait] once before waiting, if it has to wait.
  static Future<RunSlot> acquire(
    Directory directory,
    int count, {
    void Function()? onWait,
  }) async {
    if (count < 1) throw ArgumentError.value(count, 'count', 'must be >= 1');
    final slots = Directory(p.join(directory.path, 'slots'));
    await slots.create(recursive: true);
    var waited = false;
    while (true) {
      for (var i = 0; i < count; i++) {
        // Append, so opening never truncates a file another process holds.
        final file = await File(
          p.join(slots.path, '$i.lock'),
        ).open(mode: FileMode.append);
        try {
          // The default mode: exclusive, and throwing rather than waiting.
          await file.lock();
          return RunSlot._(file);
        } on FileSystemException {
          await file.close();
        }
      }
      if (!waited) {
        waited = true;
        onWait?.call();
      }
      await Future<void>.delayed(retryInterval);
    }
  }

  /// Gives the slot up.
  Future<void> release() async {
    await _file.unlock();
    await _file.close();
  }
}

/// How many runs check at once on one machine when `VERIFY_CACHE_SLOTS` is
/// unset. Two, because one agent-verify takes a 12-core machine's load
/// average from about 5 to 47, and four at once took 880 to 1,290 s each
/// against about 300 s alone, finishing no sooner than four in a row.
const defaultSlots = 2;

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

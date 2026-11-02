import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:verify_cache/verify_cache.dart';

import 'helpers.dart';

void main() {
  group(KeyLock, () {
    test('an unheld lock is taken without waiting', () async {
      var waited = false;
      final lock = await KeyLock.acquire(
        tempDir(),
        'abc',
        onWait: () => waited = true,
      );
      await lock.release();
      expect(waited, isFalse);
    });

    test('a released lock can be taken again', () async {
      final dir = tempDir();
      await (await KeyLock.acquire(dir, 'abc')).release();
      await (await KeyLock.acquire(dir, 'abc')).release();
    });

    test('waits while another process holds it, and takes it once that '
        'process dies', () async {
      final dir = tempDir();
      final holder = await holdLock(dir, 'abc');
      final waiting = Completer<void>();
      final acquired = KeyLock.acquire(dir, 'abc', onWait: waiting.complete);
      await waiting.future;
      // Killed, not released: the kernel drops the lock with the process.
      holder.kill(ProcessSignal.sigkill);
      await (await acquired).release();
    });

    test('a lock on another key does not wait', () async {
      final dir = tempDir();
      await holdLock(dir, 'abc');
      var waited = false;
      final lock = await KeyLock.acquire(
        dir,
        'abd',
        onWait: () => waited = true,
      );
      await lock.release();
      expect(waited, isFalse);
    });
  });
}

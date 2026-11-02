import 'dart:async';

import 'package:test/test.dart';
import 'package:verify_cache/verify_cache.dart';

import 'helpers.dart';

void main() {
  group(RunSlot, () {
    test('a free slot is taken without waiting', () async {
      var waited = false;
      final slot = await RunSlot.acquire(
        tempDir(),
        2,
        onWait: () => waited = true,
      );
      await slot.release();
      expect(waited, isFalse);
    });

    test('takes another slot while one is held', () async {
      final dir = tempDir();
      await holdSlot(dir, 2);
      var waited = false;
      final slot = await RunSlot.acquire(dir, 2, onWait: () => waited = true);
      await slot.release();
      expect(waited, isFalse);
    });

    test('waits while every slot is held, and takes one once its holder '
        'dies', () async {
      final dir = tempDir();
      final first = await holdSlot(dir, 2);
      await holdSlot(dir, 2);
      final waiting = Completer<void>();
      final acquired = RunSlot.acquire(dir, 2, onWait: waiting.complete);
      await waiting.future;
      // Killed, not released: the kernel drops the lock with the process.
      first.kill();
      await (await acquired).release();
    });

    test('fewer than one slot is an error', () {
      expect(() => RunSlot.acquire(tempDir(), 0), throwsArgumentError);
    });
  });

  group('slotsFromEnvironment', () {
    test('defaults to $defaultSlots', () {
      expect(slotsFromEnvironment({}), defaultSlots);
      expect(slotsFromEnvironment({'VERIFY_CACHE_SLOTS': ''}), defaultSlots);
    });

    test('reads VERIFY_CACHE_SLOTS', () {
      expect(slotsFromEnvironment({'VERIFY_CACHE_SLOTS': '3'}), 3);
    });

    test('0 is no limit', () {
      expect(slotsFromEnvironment({'VERIFY_CACHE_SLOTS': '0'}), isNull);
    });

    test('takes none inside a run that holds one', () {
      expect(slotsFromEnvironment({slotHeldVariable: '1'}), isNull);
      expect(slotsFromEnvironment({slotHeldVariable: ''}), defaultSlots);
    });

    test('a value that is not a whole number is an error', () {
      for (final value in ['two', '-1', '1.5']) {
        expect(
          () => slotsFromEnvironment({'VERIFY_CACHE_SLOTS': value}),
          throwsFormatException,
        );
      }
    });
  });
}

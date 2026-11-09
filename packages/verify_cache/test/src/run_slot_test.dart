import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
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

    test('serves waiters in arrival order', () async {
      final dir = tempDir();
      // An unlocked ticket left behind by a killed waiter is cleared.
      File(
        p.join(dir.path, 'slots', 'queue', '0'),
      ).createSync(recursive: true);

      final held = await RunSlot.acquire(dir, 1);
      final order = <int>[];

      final first = await Process.start(Platform.resolvedExecutable, [
        'run',
        p.join('test', 'fixtures', 'hold_slot.dart'),
        dir.path,
        '1',
      ]);
      addTearDown(first.kill);
      final firstLines = StreamIterator(
        first.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      expect(await firstLines.moveNext(), isTrue);
      expect(firstLines.current, 'waiting');

      final secondWaiting = Completer<void>();
      final second = RunSlot.acquire(dir, 1, onWait: secondWaiting.complete)
          .then((
            slot,
          ) async {
            order.add(2);
            await slot.release();
          });
      await secondWaiting.future;

      final thirdWaiting = Completer<void>();
      final third = RunSlot.acquire(dir, 1, onWait: thirdWaiting.complete).then(
        (
          slot,
        ) async {
          order.add(3);
          await slot.release();
        },
      );
      await thirdWaiting.future;

      await held.release();
      expect(await firstLines.moveNext(), isTrue);
      expect(firstLines.current, 'held');
      order.add(1);
      first.kill();
      await Future.wait([second, third]);
      expect(order, [1, 2, 3]);
    });

    test('fewer than one slot is an error', () {
      expect(() => RunSlot.acquire(tempDir(), 0), throwsArgumentError);
    });
  });

  group('slotsFromEnvironment', () {
    test('defaults to $defaultSlots', () {
      expect(defaultSlots, 4);
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

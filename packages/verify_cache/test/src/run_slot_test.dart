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

      final first = await startHoldSlot(dir, 1);
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

    test('a refused ticket lock leaks no descriptor', () async {
      final dir = tempDir();
      final held = await RunSlot.acquire(dir, 1);
      // Waited on before the waiter starts, so this process's locked ticket
      // is the one ahead that the waiter is refused on every try.
      final blocker = await startHoldSlot(dir, 1);
      final blockerLines = StreamIterator(
        blocker.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      expect(await blockerLines.moveNext(), isTrue);
      expect(blockerLines.current, 'waiting');

      final waiter = await startHoldSlotUnderDescriptorLimit(
        dir,
        1,
        descriptors: 128,
      );
      final lines = StreamIterator(
        waiter.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      expect(await lines.moveNext(), isTrue);
      expect(lines.current, 'waiting');
      // Four times the descriptor limit, so one descriptor leaked per try
      // exhausts it well before the last of these.
      for (var i = 0; i < 512; i++) {
        if (!await lines.moveNext()) {
          // A waiter out of descriptors dies with its cause on stderr and
          // nothing more on stdout, so the reason is only there.
          fail(
            'the waiter stopped on try $i: '
            '${await waiter.stderr.transform(utf8.decoder).join()}',
          );
        }
        expect(lines.current, 'retry');
      }

      // Killed, not released: the kernel drops the ticket's lock with the
      // process, which is what lets the waiter past it.
      blocker.kill();
      await held.release();
      while (lines.current != 'held') {
        expect(await lines.moveNext(), isTrue);
      }
    }, skip: Platform.isWindows ? 'ulimit is a POSIX shell builtin' : null);

    group('when the slot lock cannot be opened', () {
      late Directory dir;
      late Directory refusedSlot;

      setUp(() {
        dir = tempDir();
        // A directory where the slot lock goes, so the open is refused
        // whatever the uid. A mode bit only stops an unprivileged one.
        refusedSlot = Directory(p.join(dir.path, 'slots', '0.lock'))
          ..createSync(recursive: true);
      });

      test('the slot is taken on the first try that can open it', () async {
        var waited = false;
        final slot = await RunSlot.acquire(
          dir,
          1,
          onWait: () => waited = true,
          sleep: (_) async => refusedSlot.deleteSync(),
        );
        await slot.release();
        expect(waited, isTrue);
      });

      test('a ticket that cannot be unlinked still hands back the '
          'slot', () async {
        final queue = Directory(p.join(dir.path, 'slots', 'queue'));
        final slot = await RunSlot.acquire(
          dir,
          1,
          sleep: (_) async {
            refusedSlot.deleteSync();
            // Swapped for a directory, which File.deleteSync refuses
            // whatever the uid, so the slot comes back with its unlink
            // failing.
            final ticket = queue.listSync().single.path;
            File(ticket).deleteSync();
            Directory(ticket).createSync();
          },
        );
        await slot.release();
        expect(queue.listSync(), hasLength(1));
      });
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

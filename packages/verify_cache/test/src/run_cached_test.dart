import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:verify_cache/verify_cache.dart';

import 'helpers.dart';

void main() {
  group('runCached', () {
    late Directory repo;
    late Directory cache;
    late List<String> logs;
    late int runs;

    setUp(() {
      repo = gitRepo();
      cache = tempDir();
      logs = [];
      runs = 0;
    });

    /// A runner that counts its calls, does [effect] and exits [exitCode].
    CommandRunner runner({int exitCode = 0, void Function()? effect}) {
      return (command, workingDirectory) async {
        runs++;
        effect?.call();
        return exitCode;
      };
    }

    Future<int> cached({
      CommandRunner? run,
      bool force = false,
      String? workingDirectory,
      int? slots,
    }) => runCached(
      command: const ['verify'],
      workingDirectory: workingDirectory ?? repo.path,
      cacheDirectory: cache,
      tools: const ['git'],
      force: force,
      slots: slots,
      log: logs.add,
      run: run ?? runner(),
    );

    List<FileSystemEntity> entries() {
      final passed = Directory(p.join(cache.path, 'passed'));
      return passed.existsSync() ? passed.listSync() : [];
    }

    test('records a clean pass, then answers from it', () async {
      expect(await cached(), 0);
      expect(runs, 1);
      expect(entries(), hasLength(1));

      expect(await cached(), 0);
      expect(runs, 1);
      expect(logs, contains(startsWith('already verified (passed ')));
      expect(logs.where((l) => l.contains('\n')), isEmpty);
    });

    test('a second checkout of the same tree shares the pass', () async {
      await cached();
      final clone = Directory(p.join(tempDir().path, 'clone'));
      git(repo, ['clone', '-q', repo.path, clone.path]);
      expect(await cached(workingDirectory: clone.path), 0);
      expect(runs, 1);
    });

    test('a new commit is a new key', () async {
      await cached();
      File(p.join(repo.path, 'a.txt')).writeAsStringSync('changed\n');
      git(repo, ['commit', '-qam', 'change']);
      await cached();
      expect(runs, 2);
    });

    test('force runs over a recorded pass', () async {
      await cached();
      expect(await cached(force: true), 0);
      expect(runs, 2);
    });

    test('a failure is passed through and never recorded', () async {
      expect(await cached(run: runner(exitCode: 3)), 3);
      expect(entries(), isEmpty);
      await cached(run: runner(exitCode: 1));
      expect(runs, 2);
    });

    test('an uncommitted change is a new key, and passes are kept', () async {
      await cached();
      File(p.join(repo.path, 'b.txt')).writeAsStringSync('b\n');
      expect(await cached(), 0);
      expect(await cached(), 0);
      expect(runs, 2);
      expect(entries(), hasLength(2));

      // Back to the committed tree, whose pass is still recorded.
      File(p.join(repo.path, 'b.txt')).deleteSync();
      expect(await cached(), 0);
      expect(runs, 2);
    });

    test('a run that changes its inputs does not record its pass', () async {
      final run = runner(
        effect: () => File(p.join(repo.path, 'b.txt')).writeAsStringSync('b\n'),
      );
      expect(await cached(run: run), 0);
      expect(entries(), isEmpty);
      expect(logs, contains(contains('inputs changed during the run')));
    });

    group('with slots', () {
      test('a recorded pass is answered while every slot is held', () async {
        await cached();
        await holdSlot(cache, 1);
        expect(await cached(slots: 1), 0);
        expect(runs, 1);
        expect(logs, isNot(contains(contains('waiting'))));
      });

      test('a run waits for a slot, then runs', () async {
        final holder = await holdSlot(cache, 1);
        final waiting = Completer<void>();
        final run = runCached(
          command: const ['verify'],
          workingDirectory: repo.path,
          cacheDirectory: cache,
          slots: 1,
          log: (message) {
            logs.add(message);
            if (message.contains('waiting for one to finish')) {
              waiting.complete();
            }
          },
          run: runner(),
        );
        await waiting.future;
        expect(runs, 0);
        holder.kill();
        expect(await run, 0);
        expect(runs, 1);
        expect(entries(), hasLength(1));
      });
    });

    group('with inputs', () {
      setUp(() {
        for (final dir in ['in', 'out']) {
          File(p.join(repo.path, dir, 'x.txt'))
            ..parent.createSync()
            ..writeAsStringSync('$dir\n');
        }
        git(repo, ['add', '-A']);
        git(repo, ['commit', '-qm', 'dirs']);
      });

      Future<int> scoped({CommandRunner? run}) => runCached(
        command: const ['verify'],
        workingDirectory: repo.path,
        cacheDirectory: cache,
        inputs: const ['in'],
        log: logs.add,
        run: run ?? runner(),
      );

      test('a change outside them keeps the pass', () async {
        await scoped();
        File(p.join(repo.path, 'out', 'x.txt')).writeAsStringSync('new\n');
        File(p.join(repo.path, 'a.txt')).deleteSync();
        expect(await scoped(), 0);
        expect(runs, 1);
      });

      test('a change inside them is a new key', () async {
        await scoped();
        File(p.join(repo.path, 'in', 'y.txt')).writeAsStringSync('y\n');
        expect(await scoped(), 0);
        expect(runs, 2);
      });

      test('says so when one does not exist', () async {
        await runCached(
          command: const ['verify'],
          workingDirectory: repo.path,
          cacheDirectory: cache,
          inputs: const ['gone'],
          log: logs.add,
          run: runner(),
        );
        expect(logs, contains('input gone does not exist'));
      });

      test('a run that writes outside them still records', () async {
        final run = runner(
          effect: () =>
              File(p.join(repo.path, 'out', 'x.txt')).writeAsStringSync('w\n'),
        );
        expect(await scoped(run: run), 0);
        expect(entries(), hasLength(1));
      });
    });

    test('a run that commits does not record its pass', () async {
      final run = runner(
        effect: () => git(repo, ['commit', '-q', '--allow-empty', '-m', 'x']),
      );
      // An empty commit keeps the tree, so the pass still names it.
      expect(await cached(run: run), 0);
      expect(entries(), hasLength(1));
    });

    test('outside a checkout, runs and records nothing', () async {
      expect(await cached(workingDirectory: tempDir().path), 0);
      expect(runs, 1);
      expect(entries(), isEmpty);
    });

    test('a run waiting on the lock takes the pass it waited for', () async {
      await cached();
      final entry = entries().single as File;
      final digest = p.basename(entry.path);
      final aside = entry.renameSync('${entry.path}.aside');

      final holder = await holdLock(cache, digest);
      final waiting = Completer<void>();
      final waiter = runCached(
        command: const ['verify'],
        workingDirectory: repo.path,
        cacheDirectory: cache,
        tools: const ['git'],
        log: (message) {
          logs.add(message);
          if (message.contains('waiting') && !waiting.isCompleted) {
            waiting.complete();
          }
        },
        run: runner(),
      );
      await waiting.future;
      // The holder finishes its pass and exits.
      aside.renameSync(entry.path);
      holder.kill(ProcessSignal.sigkill);

      expect(await waiter, 0);
      expect(runs, 1);
      expect(logs.last, isNot(startsWith('recorded')));
    });
  });

  group('lookupPasses', () {
    test('finds the passes runCached records, in order', () async {
      final repo = gitRepo();
      final cache = tempDir();
      Future<List<bool>?> lookup() => lookupPasses(
        commands: const [
          (command: ['one'], inputs: ['a.txt']),
          (command: ['two'], inputs: ['.']),
        ],
        workingDirectory: repo.path,
        cacheDirectory: cache,
        tools: const ['git'],
      );

      expect(await lookup(), [false, false]);
      await runCached(
        command: const ['two'],
        workingDirectory: repo.path,
        cacheDirectory: cache,
        tools: const ['git'],
        log: (_) {},
        run: (_, _) async => 0,
      );
      expect(await lookup(), [false, true]);

      File(p.join(repo.path, 'b.txt')).writeAsStringSync('b\n');
      expect(await lookup(), [false, false]);
    });

    test('outside a checkout is null', () async {
      expect(
        await lookupPasses(
          commands: const [
            (command: ['one'], inputs: ['.']),
          ],
          workingDirectory: tempDir().path,
          cacheDirectory: tempDir(),
        ),
        isNull,
      );
    });
  });

  test('runInheritingStdio completes with the exit code', () async {
    expect(
      await runInheritingStdio(['sh', '-c', 'exit 3'], Directory.current.path),
      3,
    );
  });

  group('defaultCacheDirectory', () {
    test(r'prefers $VERIFY_CACHE_DIR', () {
      expect(
        defaultCacheDirectory({
          'VERIFY_CACHE_DIR': '/v',
          'XDG_CACHE_HOME': '/x',
          'HOME': '/h',
        }).path,
        '/v',
      );
    });

    test(r'then $XDG_CACHE_HOME', () {
      expect(
        defaultCacheDirectory({'XDG_CACHE_HOME': '/x', 'HOME': '/h'}).path,
        '/x/shorebird-verify-cache',
      );
    });

    test('then ~/.cache', () {
      expect(
        defaultCacheDirectory({'HOME': '/h'}).path,
        '/h/.cache/shorebird-verify-cache',
      );
    });
  });
}

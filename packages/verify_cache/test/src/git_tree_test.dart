import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:verify_cache/verify_cache.dart';

import 'helpers.dart';

void main() {
  group(GitTree, () {
    test('find is null outside a checkout', () async {
      expect(await GitTree.find(tempDir().path), isNull);
    });

    test('find reports the top level from a subdirectory', () async {
      final repo = gitRepo();
      final sub = Directory(p.join(repo.path, 'sub'))..createSync();
      expect((await GitTree.find(sub.path))!.root, repo.path);
    });

    group('workingTreeHash', () {
      late Directory repo;
      late GitTree tree;
      setUp(() {
        repo = gitRepo();
        tree = GitTree(repo.path);
      });

      void write(String path, String contents) => File(p.join(repo.path, path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(contents);

      test('of a clean checkout is HEAD^{tree}', () async {
        expect(
          await tree.workingTreeHash(),
          git(repo, ['rev-parse', 'HEAD^{tree}']),
        );
      });

      test('is the tree a commit of everything on disk would have', () async {
        write('a.txt', 'changed\n');
        write('b.txt', 'b\n');
        final hash = await tree.workingTreeHash();
        expect(hash, isNot(git(repo, ['rev-parse', 'HEAD^{tree}'])));

        git(repo, ['add', '-A']);
        git(repo, ['commit', '-qm', 'everything']);
        expect(hash, git(repo, ['rev-parse', 'HEAD^{tree}']));
      });

      test('counts a deleted file', () async {
        final clean = await tree.workingTreeHash();
        File(p.join(repo.path, 'a.txt')).deleteSync();
        expect(await tree.workingTreeHash(), isNot(clean));
      });

      test('leaves the checkout index alone', () async {
        write('b.txt', 'b\n');
        await tree.workingTreeHash();
        expect(git(repo, ['status', '--porcelain']), '?? b.txt');
      });

      test('does not count an ignored file', () async {
        write('.gitignore', 'out/\n');
        git(repo, ['add', '.gitignore']);
        git(repo, ['commit', '-qm', 'ignore']);
        final clean = await tree.workingTreeHash();
        write('out/x', 'x\n');
        expect(await tree.workingTreeHash(), clean);
      });

      test('works in a checkout with no commits', () async {
        final dir = tempDir();
        git(dir, ['init', '-q']);
        File(p.join(dir.path, 'a.txt')).writeAsStringSync('a\n');
        expect(await GitTree(dir.path).workingTreeHash(), isNotNull);
      });

      test('works in a linked worktree', () async {
        final linked = p.join(tempDir().path, 'linked');
        git(repo, ['worktree', 'add', '-q', '--detach', linked]);
        expect(
          await GitTree(linked).workingTreeHash(),
          git(repo, ['rev-parse', 'HEAD^{tree}']),
        );
      });
    });

    group('hashesIn', () {
      test(
        'hashes each path, the root as ., and a missing one as absent',
        () async {
          final repo = gitRepo();
          File(p.join(repo.path, 'd', 'x.txt'))
            ..parent.createSync()
            ..writeAsStringSync('x\n');
          git(repo, ['add', '-A']);
          git(repo, ['commit', '-qm', 'd']);
          final head = git(repo, ['rev-parse', 'HEAD^{tree}']);

          expect(
            await GitTree(
              repo.path,
            ).hashesIn(head, ['.', 'a.txt', 'd', 'nope']),
            {
              '.': head,
              'a.txt': git(repo, ['rev-parse', 'HEAD:a.txt']),
              'd': git(repo, ['rev-parse', 'HEAD:d']),
              'nope': 'absent',
            },
          );
        },
      );

      test('is null for a tree git does not have', () async {
        final repo = gitRepo();
        expect(await GitTree(repo.path).hashesIn('0' * 40, ['a.txt']), isNull);
      });
    });
  });
}

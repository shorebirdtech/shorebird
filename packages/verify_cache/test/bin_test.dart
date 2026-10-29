import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:verify_cache/verify_cache.dart';

import 'src/helpers.dart';

void main() {
  final bin = p.absolute('bin', 'verify_cache.dart');

  Future<ProcessResult> verifyCache(
    Directory repo,
    List<String> args, {
    Map<String, String> environment = const {},
  }) => Process.run(
    Platform.resolvedExecutable,
    [bin, ...args],
    workingDirectory: repo.path,
    // These tests may themselves run under a verify_cache holding a slot.
    environment: {slotHeldVariable: '', ...environment},
  );

  test('runs the command once, then answers from the cache', () async {
    final repo = gitRepo();
    final cache = tempDir();
    final args = ['--cache-dir', cache.path, '--', 'git', 'status'];

    final first = await verifyCache(repo, args);
    expect(first.exitCode, 0);
    expect(first.stdout, contains('nothing to commit'));
    expect(first.stdout, contains('recorded this pass'));

    final second = await verifyCache(repo, args);
    expect(second.exitCode, 0);
    expect(second.stdout, isNot(contains('nothing to commit')));
    expect(second.stdout, contains('already verified'));
  });

  test("exits with the command's code", () async {
    final result = await verifyCache(gitRepo(), [
      '--cache-dir',
      tempDir().path,
      '--',
      'git',
      'no-such-subcommand',
    ]);
    expect(result.exitCode, isNot(0));
  });

  test('options after the command belong to the command', () async {
    final result = await verifyCache(gitRepo(), [
      '--cache-dir',
      tempDir().path,
      'git',
      '--force',
    ]);
    // git rejects --force, so it reached git rather than this tool.
    expect(result.exitCode, isNot(0));
    expect(result.stdout, isNot(contains('--force, running')));
  });

  test('tells the command it runs under a slot', () async {
    final result = await verifyCache(gitRepo(), [
      '--cache-dir',
      tempDir().path,
      '--',
      'sh',
      '-c',
      'echo "held=\$$slotHeldVariable"',
    ]);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('held=1'));
  });

  test('VERIFY_CACHE_SLOTS=0 takes no slot', () async {
    final result = await verifyCache(
      gitRepo(),
      [
        '--cache-dir',
        tempDir().path,
        '--',
        'sh',
        '-c',
        'echo "held=\$$slotHeldVariable"',
      ],
      environment: {'VERIFY_CACHE_SLOTS': '0'},
    );
    expect(result.exitCode, 0);
    expect(result.stdout, contains('held=\n'));
  });

  test('a bad VERIFY_CACHE_SLOTS is a usage error', () async {
    final result = await verifyCache(
      gitRepo(),
      ['--', 'true'],
      environment: {'VERIFY_CACHE_SLOTS': 'many'},
    );
    expect(result.exitCode, 2);
    expect(result.stderr, contains('VERIFY_CACHE_SLOTS'));
  });

  test('no command is a usage error', () async {
    final result = await verifyCache(gitRepo(), ['--force']);
    expect(result.exitCode, 2);
    expect(result.stderr, contains('usage:'));
  });

  test('an unknown option is a usage error', () async {
    final result = await verifyCache(gitRepo(), ['--nope', '--', 'true']);
    expect(result.exitCode, 2);
  });

  test('--dart-package keys on the package closure only', () async {
    final repo = gitRepo();
    final cache = tempDir();
    for (final dir in ['packages/app', 'packages/other']) {
      File(p.join(repo.path, dir, 'pubspec.yaml'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('name: x\n');
    }
    git(repo, ['add', '-A']);
    git(repo, ['commit', '-qm', 'packages']);
    final args = [
      '--cache-dir',
      cache.path,
      '--dart-package',
      'packages/app',
      '--',
      'true',
    ];

    expect((await verifyCache(repo, args)).stdout, contains('recorded'));
    File(
      p.join(repo.path, 'packages/other/lib.dart'),
    ).writeAsStringSync('// x\n');
    expect(
      (await verifyCache(repo, args)).stdout,
      contains('already verified'),
    );
    File(p.join(repo.path, 'packages/app/lib.dart')).writeAsStringSync('//\n');
    expect((await verifyCache(repo, args)).stdout, contains('recorded'));
  });

  group('--lookup', () {
    late Directory repo;
    late Directory cache;
    setUp(() {
      repo = gitRepo();
      cache = tempDir();
      for (final dir in ['packages/app', 'packages/other']) {
        File(p.join(repo.path, dir, 'pubspec.yaml'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('name: x\n');
      }
    });

    List<String> run(String package) => [
      '--cache-dir',
      cache.path,
      '--dart-package',
      package,
      '--input',
      'a.txt',
      '--tool',
      'git',
      '--',
      'echo',
      package,
    ];

    Future<String> lookup() async {
      final result = await verifyCache(repo, [
        '--lookup',
        '--cache-dir',
        cache.path,
        '--dart-package',
        'packages/app',
        '--dart-package',
        'packages/other',
        '--input',
        'a.txt',
        '--tool',
        'git',
        '--',
        'echo',
        '{}',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return (result.stdout as String).trim();
    }

    // The keys it reads must be the ones a run records, or every lookup
    // misses and the caller runs every package as before.
    test('lists the packages a run already passed, and runs none', () async {
      expect(await lookup(), '[]');
      expect(
        (await verifyCache(repo, run('packages/app'))).stdout,
        contains('recorded'),
      );
      expect(await lookup(), '["packages/app"]');
      expect(
        (await verifyCache(repo, run('packages/other'))).stdout,
        contains('recorded'),
      );
      expect(await lookup(), '["packages/app","packages/other"]');
    });

    test('drops a package whose inputs changed', () async {
      await verifyCache(repo, run('packages/app'));
      await verifyCache(repo, run('packages/other'));
      File(
        p.join(repo.path, 'packages/app/lib.dart'),
      ).writeAsStringSync('//\n');
      expect(await lookup(), '["packages/other"]');
      File(p.join(repo.path, 'a.txt')).writeAsStringSync('changed\n');
      expect(await lookup(), '[]');
    });

    test('with no --dart-package is a usage error', () async {
      final result = await verifyCache(repo, ['--lookup', '--', 'true']);
      expect(result.exitCode, 2);
    });
  });

  test('two --dart-package without --lookup is a usage error', () async {
    final result = await verifyCache(gitRepo(), [
      '--dart-package',
      'a',
      '--dart-package',
      'b',
      '--',
      'true',
    ]);
    expect(result.exitCode, 2);
    expect(result.stderr, contains('--lookup'));
  });

  test('--dart-package with a bad pubspec is a usage error', () async {
    final repo = gitRepo();
    File(p.join(repo.path, 'app', 'pubspec.yaml'))
      ..parent.createSync()
      ..writeAsStringSync('- a list\n');
    final result = await verifyCache(repo, [
      '--dart-package',
      'app',
      '--',
      'true',
    ]);
    expect(result.exitCode, 2);
  });

  test('--dart-package outside a checkout is a usage error', () async {
    final result = await verifyCache(tempDir(), [
      '--dart-package',
      'app',
      '--',
      'true',
    ]);
    expect(result.exitCode, 2);
  });

  test('--input keys on the paths given', () async {
    final repo = gitRepo();
    final cache = tempDir();
    final args = ['--cache-dir', cache.path, '--input', 'a.txt', '--', 'true'];
    expect((await verifyCache(repo, args)).stdout, contains('recorded'));
    File(p.join(repo.path, 'b.txt')).writeAsStringSync('b\n');
    expect(
      (await verifyCache(repo, args)).stdout,
      contains('already verified'),
    );
  });

  test('--help prints the usage', () async {
    final result = await verifyCache(gitRepo(), ['--help']);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('--tool'));
  });
}

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/commands/commands.dart';
import 'package:shorebird_ci/src/zizmor.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A command no machine has, so [Zizmor.ensure] never finds one on PATH.
const _noZizmor = 'shorebird_ci_test_no_zizmor';

const _linuxX64 = 'zizmor-x86_64-unknown-linux-gnu.tar.gz';

void main() {
  setUpTempDir('shorebird_ci_zizmor_');

  group('zizmorAssetFor', () {
    test('names a pinned asset for each platform zizmor publishes', () {
      for (final abi in [
        Abi.linuxX64,
        Abi.linuxArm64,
        Abi.macosX64,
        Abi.macosArm64,
        Abi.windowsX64,
        Abi.windowsArm64,
      ]) {
        final asset = zizmorAssetFor(abi);
        expect(zizmorSha256, contains(asset), reason: '$abi');
      }
      expect(zizmorAssetFor(Abi.windowsArm64), contains('x86_64'));
    });

    test('is null where zizmor publishes nothing', () {
      expect(zizmorAssetFor(Abi.androidArm64), isNull);
    });

    test('every pin is a SHA-256', () {
      for (final sha in zizmorSha256.values) {
        expect(sha, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
    });
  });

  group('Zizmor.ensure', () {
    test('throws when zizmor publishes nothing for the platform', () {
      final zizmor = Zizmor(
        cacheDir: tempDir.path,
        abi: Abi.androidArm64,
        onPath: _noZizmor,
      );
      expect(zizmor.ensure, throwsA(isA<ZizmorException>()));
    });

    test('throws when the download fails', () {
      final zizmor = Zizmor(
        cacheDir: tempDir.path,
        abi: Abi.linuxX64,
        onPath: _noZizmor,
        download: (_) async => throw const SocketException('offline'),
      );
      expect(
        zizmor.ensure,
        throwsA(
          isA<ZizmorException>().having(
            (e) => e.message,
            'message',
            contains('could not download'),
          ),
        ),
      );
    });

    test('refuses a download whose SHA-256 is not the pin', () async {
      final zizmor = Zizmor(
        cacheDir: tempDir.path,
        abi: Abi.linuxX64,
        onPath: _noZizmor,
        download: (_) async => [1, 2, 3],
      );
      await expectLater(
        zizmor.ensure,
        throwsA(
          isA<ZizmorException>().having(
            (e) => e.toString(),
            'message',
            contains('expected ${zizmorSha256[_linuxX64]}'),
          ),
        ),
      );
      expect(tempDir.listSync(), isEmpty);
    });

    test('uses a copy already in the cache without downloading', () async {
      final cached = File(p.join(tempDir.path, zizmorVersion, 'zizmor'))
        ..createSync(recursive: true);
      final zizmor = Zizmor(
        cacheDir: tempDir.path,
        abi: Abi.linuxX64,
        onPath: _noZizmor,
        download: (_) async => fail('downloaded'),
      );
      expect(await zizmor.ensure(), cached.path);
    });

    test(
      'uses a zizmor on PATH only at the pinned version',
      () async {
        File script(String version) {
          final file = File(p.join(tempDir.path, 'zizmor-$version'))
            ..writeAsStringSync('#!/bin/sh\necho "zizmor $version"\n');
          Process.runSync('chmod', ['+x', file.path]);
          return file;
        }

        final pinned = script(zizmorVersion);
        expect(
          await Zizmor(cacheDir: tempDir.path, onPath: pinned.path).ensure(),
          pinned.path,
        );

        final other = script('0.0.1');
        await expectLater(
          Zizmor(
            cacheDir: tempDir.path,
            abi: Abi.androidArm64,
            onPath: other.path,
          ).ensure,
          throwsA(isA<ZizmorException>()),
        );
      },
      skip: Platform.isWindows ? 'runs a shell script' : null,
    );

    test("extracts with Windows' own tar there", () {
      expect(
        Zizmor(abi: Abi.windowsX64, environment: {'SystemRoot': r'D:\Win'}).tar,
        p.join(r'D:\Win', 'System32', 'tar'),
      );
      expect(Zizmor(abi: Abi.linuxX64).tar, 'tar');
    });

    test('has a per-user cache directory', () {
      expect(
        Zizmor(abi: Abi.linuxX64, environment: {'HOME': '/home/u'}).cacheDir,
        p.join('/home/u', '.cache', 'shorebird_ci', 'zizmor'),
      );
      expect(
        Zizmor(
          abi: Abi.linuxX64,
          environment: {'XDG_CACHE_HOME': '/c', 'HOME': '/home/u'},
        ).cacheDir,
        p.join('/c', 'shorebird_ci', 'zizmor'),
      );
      expect(
        Zizmor(
          abi: Abi.windowsX64,
          environment: {'LOCALAPPDATA': r'C:\Users\u\AppData\Local'},
        ).cacheDir,
        p.join(r'C:\Users\u\AppData\Local', 'shorebird_ci', 'zizmor'),
      );
    });
  });

  // Downloads the pinned release (or uses a zizmor on PATH at that
  // version) and runs it over what `generate` writes for a repository
  // using every feature that changes the output.
  group('generated workflows', () {
    void createRepository() {
      for (final (name, flutter) in [('a', false), ('b', true)]) {
        final dir = Directory(p.join(tempDir.path, 'packages', name))
          ..createSync(recursive: true);
        File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: $name
environment:
  sdk: ^3.0.0
${flutter ? 'dependencies:\n  flutter:\n    sdk: flutter\n' : ''}dev_dependencies:
  bloc_lint: any
shorebird_ci:
  needs_redis: ${!flutter}
  min_coverage: 90
  runners: [ubuntu-latest, windows-latest]
''');
        File(p.join(dir.path, 'test', '${name}_test.dart'))
          ..createSync(recursive: true)
          ..writeAsStringSync('void main() {}');
        if (flutter) {
          Directory(p.join(dir.path, 'integration_test')).createSync();
          Directory(p.join(dir.path, 'linux')).createSync();
          Directory(p.join(dir.path, 'packages', 'sub')).createSync(
            recursive: true,
          );
          File(
            p.join(dir.path, 'packages', 'sub', 'pubspec.yaml'),
          ).writeAsStringSync('name: sub\nenvironment:\n  sdk: ^3.0.0\n');
        }
      }
      File(p.join(tempDir.path, 'cspell.json')).writeAsStringSync('{}');
      File(p.join(tempDir.path, 'codecov.yml')).writeAsStringSync('');
      File(p.join(tempDir.path, '.gitmodules')).writeAsStringSync(
        '[submodule "x"]\n\tpath = x\n\turl = https://example.com/x\n',
      );
      initGitRepo(tempDir);
    }

    // A cache of this group's own, so every run downloads, checks and
    // extracts the release rather than finding it already there.
    late Directory cache;
    late Zizmor zizmor;
    setUpAll(() async {
      cache = Directory.systemTemp.createTempSync('shorebird_ci_zizmor_cache_');
      zizmor = Zizmor(cacheDir: cache.path, onPath: _noZizmor);
      await zizmor.ensure();
    });
    tearDownAll(() => cache.deleteSync(recursive: true));

    for (final style in ['dynamic', 'static']) {
      test(
        '--style $style has no zizmor findings',
        () async {
          createRepository();
          final runner = CommandRunner<int>('test', 'test')
            ..addCommand(GenerateCommand());
          final code = await runner.run([
            'generate',
            '--repo-root',
            tempDir.path,
            '--style',
            style,
            '--required',
            '--fatal-infos',
            '--codecov-token-secret',
            'CODECOV_TOKEN',
            '--no-update-actions',
            '--no-zizmor',
          ]);
          expect(code, 0);

          final result = await zizmor.run(tempDir.path);
          expect(result.exitCode, 0, reason: result.stdout);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  });
}

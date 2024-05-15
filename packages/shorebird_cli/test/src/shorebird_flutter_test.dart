import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(ShorebirdFlutter, () {
    const flutterRevision = 'flutter-revision';
    late Directory shorebirdRoot;
    late Directory flutterDirectory;
    late Git git;
    late ShorebirdLogger logger;
    late Platform platform;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess process;
    late ShorebirdProcessResult versionProcessResult;
    late ShorebirdProcessResult precacheProcessResult;
    late ShorebirdFlutter shorebirdFlutter;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          gitRef.overrideWith(() => git),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => process),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      shorebirdRoot = Directory.systemTemp.createTempSync();
      flutterDirectory = Directory(p.join(shorebirdRoot.path, 'flutter'));
      git = MockGit();
      logger = MockShorebirdLogger();
      progress = MockProgress();
      shorebirdEnv = MockShorebirdEnv();
      platform = MockPlatform();
      process = MockShorebirdProcess();
      versionProcessResult = MockShorebirdProcessResult();
      precacheProcessResult = MockShorebirdProcessResult();
      shorebirdFlutter = runWithOverrides(ShorebirdFlutter.new);

      when(
        () => git.clone(
          url: any(named: 'url'),
          outputDirectory: any(named: 'outputDirectory'),
          args: any(named: 'args'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => git.checkout(
          directory: any(named: 'directory'),
          revision: any(named: 'revision'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => git.status(
          directory: p.join(flutterDirectory.parent.path, flutterRevision),
          args: ['--untracked-files=no', '--porcelain'],
        ),
      ).thenAnswer((_) async => '');
      when(
        () => git.revParse(
          revision: any(named: 'revision'),
          directory: any(named: 'directory'),
        ),
      ).thenAnswer((_) async => flutterRevision);
      when(
        () => git.forEachRef(
          directory: any(named: 'directory'),
          contains: any(named: 'contains'),
          format: any(named: 'format'),
          pattern: any(named: 'pattern'),
        ),
      ).thenAnswer((_) async => 'origin/flutter_release/3.10.6');
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => platform.isMacOS).thenReturn(false);
      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(
        () => process.run(
          'flutter',
          ['--version'],
          runInShell: true,
          useVendedFlutter: false,
        ),
      ).thenAnswer((_) async => versionProcessResult);
      when(() => versionProcessResult.exitCode).thenReturn(0);
      when(
        () => process.run(
          'flutter',
          any(that: contains('precache')),
          runInShell: true,
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => precacheProcessResult);
      when(() => versionProcessResult.exitCode).thenReturn(0);
    });

    group('precacheArgs', () {
      group('when running on macOS', () {
        setUp(() {
          when(() => platform.isMacOS).thenReturn(true);
        });

        test('includes ios in platform list', () async {
          expect(
            runWithOverrides(() => shorebirdFlutter.precacheArgs),
            contains('--ios'),
          );
        });
      });

      group('when not running on macOS', () {
        setUp(() {
          when(() => platform.isMacOS).thenReturn(false);
        });

        test('does not include ios in platform list', () {
          expect(
            runWithOverrides(() => shorebirdFlutter.precacheArgs),
            isNot(contains('--ios')),
          );
        });
      });
    });

    group('getSystemVersion', () {
      test('throws ProcessException when process exits with non-zero code',
          () async {
        const error = 'oops';
        when(() => versionProcessResult.exitCode)
            .thenReturn(ExitCode.software.code);
        when(() => versionProcessResult.stderr).thenReturn(error);
        await expectLater(
          runWithOverrides(shorebirdFlutter.getSystemVersion),
          throwsA(isA<ProcessException>()),
        );
        verify(
          () => process.run(
            'flutter',
            ['--version'],
            runInShell: true,
            useVendedFlutter: false,
          ),
        ).called(1);
      });

      test('returns null when cannot parse version', () async {
        when(() => versionProcessResult.stdout).thenReturn('');
        await expectLater(
          runWithOverrides(shorebirdFlutter.getSystemVersion),
          completion(isNull),
        );
        verify(
          () => process.run(
            'flutter',
            ['--version'],
            runInShell: true,
            useVendedFlutter: false,
          ),
        ).called(1);
      });

      test('returns version when able to parse the string', () async {
        when(() => versionProcessResult.stdout).thenReturn('''
Flutter 3.10.6 • channel stable • git@github.com:flutter/flutter.git
Framework • revision f468f3366c (4 weeks ago) • 2023-07-12 15:19:05 -0700
Engine • revision cdbeda788a
Tools • Dart 3.0.6 • DevTools 2.23.1''');
        await expectLater(
          runWithOverrides(shorebirdFlutter.getSystemVersion),
          completion(equals('3.10.6')),
        );
        verify(
          () => process.run(
            'flutter',
            ['--version'],
            runInShell: true,
            useVendedFlutter: false,
          ),
        ).called(1);
      });
    });

    group('getVersionAndRevision', () {
      test('returns unknown (<revision>) when unable to determine version',
          () async {
        const error = 'oops';
        when(
          () => git.forEachRef(
            directory: any(named: 'directory'),
            contains: any(named: 'contains'),
            format: any(named: 'format'),
            pattern: any(named: 'pattern'),
          ),
        ).thenThrow(
          ProcessException(
            'git',
            [
              'for-each-ref',
              '--format',
              '%(refname:short)',
              'refs/remotes/origin/flutter_release/*',
            ],
            error,
            ExitCode.software.code,
          ),
        );
        await expectLater(
          runWithOverrides(shorebirdFlutter.getVersionAndRevision),
          completion(equals('unknown (${flutterRevision.substring(0, 10)})')),
        );
      });

      test('returns correct version and revision', () async {
        await expectLater(
          runWithOverrides(shorebirdFlutter.getVersionAndRevision),
          completion(equals('3.10.6 (${flutterRevision.substring(0, 10)})')),
        );
      });
    });

    group('getRevisionForVersion', () {
      const version = '3.16.3';

      test('throws exception when process exits with non-zero code', () async {
        const exception = ProcessException('git', ['rev-parse']);
        when(
          () => git.revParse(
            revision: any(named: 'revision'),
            directory: any(named: 'directory'),
          ),
        ).thenThrow(exception);
        await expectLater(
          runWithOverrides(
            () => shorebirdFlutter.getRevisionForVersion(version),
          ),
          throwsA(exception),
        );
        verify(
          () => git.revParse(
            revision: 'refs/remotes/origin/flutter_release/$version',
            directory: any(named: 'directory'),
          ),
        ).called(1);
      });

      test('returns null when cannot parse revision', () async {
        when(
          () => git.revParse(
            revision: any(named: 'revision'),
            directory: any(named: 'directory'),
          ),
        ).thenAnswer((_) async => '');
        await expectLater(
          runWithOverrides(
            () => shorebirdFlutter.getRevisionForVersion(version),
          ),
          completion(isNull),
        );
        verify(
          () => git.revParse(
            revision: 'refs/remotes/origin/flutter_release/$version',
            directory: any(named: 'directory'),
          ),
        ).called(1);
      });

      test('returns revision when able to parse the string', () async {
        const revision = '771d07b2cf97cf107bae6eeedcf41bdc9db772fa';
        when(
          () => git.revParse(
            revision: any(named: 'revision'),
            directory: any(named: 'directory'),
          ),
        ).thenAnswer(
          (_) async => '''
$revision
        ''',
        );
        await expectLater(
          runWithOverrides(
            () => shorebirdFlutter.getRevisionForVersion(version),
          ),
          completion(equals(revision)),
        );
        verify(
          () => git.revParse(
            revision: 'refs/remotes/origin/flutter_release/$version',
            directory: any(named: 'directory'),
          ),
        ).called(1);
      });
    });

    group('getVersionString', () {
      test('throws ProcessException when process exits with non-zero code',
          () async {
        const error = 'oops';
        when(
          () => git.forEachRef(
            directory: any(named: 'directory'),
            contains: any(named: 'contains'),
            format: any(named: 'format'),
            pattern: any(named: 'pattern'),
          ),
        ).thenThrow(
          ProcessException(
            'git',
            [
              'for-each-ref',
              '--format',
              '%(refname:short)',
              'refs/remotes/origin/flutter_release/*',
            ],
            error,
            ExitCode.software.code,
          ),
        );
        await expectLater(
          runWithOverrides(shorebirdFlutter.getVersionString),
          throwsA(isA<ProcessException>()),
        );
        verify(
          () => git.forEachRef(
            directory: p.join(flutterDirectory.parent.path, flutterRevision),
            contains: flutterRevision,
            format: '%(refname:short)',
            pattern: 'refs/remotes/origin/flutter_release/*',
          ),
        ).called(1);
      });

      test('returns null when cannot parse version', () async {
        when(
          () => git.forEachRef(
            directory: any(named: 'directory'),
            contains: any(named: 'contains'),
            format: any(named: 'format'),
            pattern: any(named: 'pattern'),
          ),
        ).thenAnswer((_) async => '');
        await expectLater(
          runWithOverrides(shorebirdFlutter.getVersionString),
          completion(isNull),
        );
        verify(
          () => git.forEachRef(
            directory: p.join(flutterDirectory.parent.path, flutterRevision),
            contains: flutterRevision,
            format: '%(refname:short)',
            pattern: 'refs/remotes/origin/flutter_release/*',
          ),
        ).called(1);
      });

      test('returns version when able to parse the string', () async {
        await expectLater(
          runWithOverrides(shorebirdFlutter.getVersionString),
          completion(equals('3.10.6')),
        );
        verify(
          () => git.forEachRef(
            directory: p.join(flutterDirectory.parent.path, flutterRevision),
            contains: flutterRevision,
            format: '%(refname:short)',
            pattern: 'refs/remotes/origin/flutter_release/*',
          ),
        ).called(1);
      });
    });

    group('getVersion', () {
      group('when getVersionString returns null', () {
        setUp(() {
          when(
            () => git.forEachRef(
              directory: any(named: 'directory'),
              contains: any(named: 'contains'),
              format: any(named: 'format'),
              pattern: any(named: 'pattern'),
            ),
          ).thenAnswer((_) async => '');
        });

        test('returns null', () {
          expect(
            runWithOverrides(shorebirdFlutter.getVersion),
            completion(isNull),
          );
        });
      });

      group('when getVersionStringReturns an invalid string', () {
        setUp(() {
          when(
            () => git.forEachRef(
              directory: any(named: 'directory'),
              contains: any(named: 'contains'),
              format: any(named: 'format'),
              pattern: any(named: 'pattern'),
            ),
          ).thenAnswer((_) async => 'not a version');
        });

        test('returns null', () {
          expect(
            runWithOverrides(shorebirdFlutter.getVersion),
            completion(isNull),
          );
        });
      });

      group('when getVersionStringReturns a valid string', () {
        setUp(() {
          when(
            () => git.forEachRef(
              directory: any(named: 'directory'),
              contains: any(named: 'contains'),
              format: any(named: 'format'),
              pattern: any(named: 'pattern'),
            ),
          ).thenAnswer((_) async => '3.10.6');
        });

        test('returns the version', () {
          expect(
            runWithOverrides(shorebirdFlutter.getVersion),
            completion(equals(Version(3, 10, 6))),
          );
        });
      });
    });

    group('getVersions', () {
      const format = '%(refname:short)';
      const pattern = 'refs/remotes/origin/flutter_release/*';
      test('returns a list of versions', () async {
        const versions = [
          '3.10.0',
          '3.10.1',
          '3.10.2',
          '3.10.3',
          '3.10.4',
          '3.10.5',
          '3.10.6',
        ];
        const output = '''
origin/flutter_release/3.10.0
origin/flutter_release/3.10.1
origin/flutter_release/3.10.2
origin/flutter_release/3.10.3
origin/flutter_release/3.10.4
origin/flutter_release/3.10.5
origin/flutter_release/3.10.6''';
        when(
          () => git.forEachRef(
            directory: any(named: 'directory'),
            format: any(named: 'format'),
            pattern: any(named: 'pattern'),
          ),
        ).thenAnswer((_) async => output);

        await expectLater(
          runWithOverrides(shorebirdFlutter.getVersions),
          completion(equals(versions)),
        );
        verify(
          () => git.forEachRef(
            directory: p.join(flutterDirectory.parent.path, flutterRevision),
            format: format,
            pattern: pattern,
          ),
        ).called(1);
      });

      test('throws ProcessException when git command exits non-zero code',
          () async {
        const errorMessage = 'oh no!';
        when(
          () => git.forEachRef(
            directory: any(named: 'directory'),
            format: any(named: 'format'),
            pattern: any(named: 'pattern'),
          ),
        ).thenThrow(
          ProcessException(
            'git',
            ['for-each-ref', '--format', format, pattern],
            errorMessage,
            ExitCode.software.code,
          ),
        );

        expect(
          runWithOverrides(shorebirdFlutter.getVersions),
          throwsA(
            isA<ProcessException>().having(
              (e) => e.message,
              'message',
              errorMessage,
            ),
          ),
        );
      });
    });

    group('installRevision', () {
      const revision = 'test-revision';

      test('does nothing if the revision is already installed', () async {
        Directory(
          p.join(flutterDirectory.parent.path, revision),
        ).createSync(recursive: true);

        await runWithOverrides(
          () => shorebirdFlutter.installRevision(revision: revision),
        );

        verifyNever(
          () => git.clone(
            url: any(named: 'url'),
            outputDirectory: any(named: 'outputDirectory'),
            args: any(named: 'args'),
          ),
        );
        verifyNever(
          () => process.run(
            'flutter',
            any(that: contains('precache')),
            runInShell: any(named: 'runInShell'),
          ),
        );
      });

      test('throws exception if unable to clone', () async {
        final exception = Exception('oops');
        when(
          () => git.clone(
            url: any(named: 'url'),
            outputDirectory: any(named: 'outputDirectory'),
            args: any(named: 'args'),
          ),
        ).thenThrow(exception);

        await expectLater(
          runWithOverrides(
            () => shorebirdFlutter.installRevision(revision: revision),
          ),
          throwsA(exception),
        );

        verify(
          () => git.clone(
            url: ShorebirdFlutter.flutterGitUrl,
            outputDirectory: p.join(flutterDirectory.parent.path, revision),
            args: ['--filter=tree:0', '--no-checkout'],
          ),
        ).called(1);
        verifyNever(
          () => process.run(
            'flutter',
            any(that: contains('precache')),
            runInShell: any(named: 'runInShell'),
          ),
        );
      });

      test('throws exception if unable to checkout revision', () async {
        final exception = Exception('oops');
        when(
          () => git.checkout(
            directory: any(named: 'directory'),
            revision: any(named: 'revision'),
          ),
        ).thenThrow(exception);

        await expectLater(
          runWithOverrides(
            () => shorebirdFlutter.installRevision(revision: revision),
          ),
          throwsA(exception),
        );
        verify(
          () => git.clone(
            url: ShorebirdFlutter.flutterGitUrl,
            outputDirectory: p.join(flutterDirectory.parent.path, revision),
            args: ['--filter=tree:0', '--no-checkout'],
          ),
        ).called(1);
        verify(
          () => git.checkout(
            directory: p.join(flutterDirectory.parent.path, revision),
            revision: revision,
          ),
        ).called(1);
        verify(
          () => logger.progress(
            'Installing Flutter 3.10.6 (test-revis)',
          ),
        ).called(1);
        verify(
          () => progress.fail(
            'Failed to install Flutter 3.10.6 (test-revis)',
          ),
        ).called(1);
      });

      group('when unable to precache', () {
        setUp(() {
          when(
            () => process.run(
              'flutter',
              any(that: contains('precache')),
              workingDirectory: any(named: 'workingDirectory'),
              runInShell: any(named: 'runInShell'),
            ),
          ).thenThrow(Exception('oh no!'));
        });

        test('logs error and continues', () async {
          await expectLater(
            runWithOverrides(
              () => shorebirdFlutter.installRevision(revision: revision),
            ),
            completes,
          );
          verify(
            () => process.run(
              'flutter',
              [
                'precache',
                ...runWithOverrides(() => shorebirdFlutter.precacheArgs),
              ],
              workingDirectory: p.join(
                flutterDirectory.parent.path,
                revision,
              ),
              runInShell: true,
            ),
          ).called(1);

          verify(
            () => progress.fail('Failed to precache Flutter 3.10.6'),
          ).called(1);
          verify(
            () => logger.info(
              '''This is not a critical error, but your next build make take longer than usual.''',
            ),
          ).called(1);
        });
      });

      group('when clone and checkout succeed', () {
        test('completes successfully', () async {
          await expectLater(
            runWithOverrides(
              () => shorebirdFlutter.installRevision(revision: revision),
            ),
            completes,
          );
          verify(
            () => process.run(
              'flutter',
              [
                'precache',
                ...runWithOverrides(() => shorebirdFlutter.precacheArgs),
              ],
              workingDirectory: p.join(
                flutterDirectory.parent.path,
                revision,
              ),
              runInShell: true,
            ),
          ).called(1);
          verify(
            () => logger.progress(
              'Installing Flutter 3.10.6 (test-revis)',
            ),
          ).called(1);
          // Once for the installation and once for the precache.
          verify(progress.complete).called(2);
        });
      });
    });

    group('isPorcelain', () {
      test('returns true when status is empty', () async {
        await expectLater(
          runWithOverrides(() => shorebirdFlutter.isUnmodified()),
          completion(isTrue),
        );
        verify(
          () => git.status(
            directory: p.join(flutterDirectory.parent.path, flutterRevision),
            args: ['--untracked-files=no', '--porcelain'],
          ),
        ).called(1);
      });

      test('returns false when status is not empty', () async {
        when(
          () => git.status(
            directory: any(named: 'directory'),
            args: any(named: 'args'),
          ),
        ).thenAnswer((_) async => 'M some/file');
        await expectLater(
          runWithOverrides(() => shorebirdFlutter.isUnmodified()),
          completion(isFalse),
        );
        verify(
          () => git.status(
            directory: p.join(flutterDirectory.parent.path, flutterRevision),
            args: ['--untracked-files=no', '--porcelain'],
          ),
        ).called(1);
      });

      test('throws ProcessException when git command exits non-zero code',
          () async {
        const errorMessage = 'oh no!';
        when(
          () => git.status(
            directory: any(named: 'directory'),
            args: any(named: 'args'),
          ),
        ).thenThrow(
          ProcessException(
            'git',
            ['status'],
            errorMessage,
            ExitCode.software.code,
          ),
        );

        expect(
          runWithOverrides(() => shorebirdFlutter.isUnmodified()),
          throwsA(
            isA<ProcessException>().having(
              (e) => e.message,
              'message',
              errorMessage,
            ),
          ),
        );
      });
    });

    group('useRevision', () {
      const revision = 'new-revision';

      test('installs revision if it does not exist', () async {
        await expectLater(
          runWithOverrides(
            () => shorebirdFlutter.useRevision(revision: revision),
          ),
          completes,
        );
        verify(
          () => git.clone(
            url: ShorebirdFlutter.flutterGitUrl,
            outputDirectory: p.join(
              flutterDirectory.parent.path,
              revision,
            ),
            args: ['--filter=tree:0', '--no-checkout'],
          ),
        ).called(1);
        verify(() => shorebirdEnv.flutterRevision = revision).called(1);
      });

      test('skips installation if revision already exists', () async {
        Directory(p.join(flutterDirectory.parent.path, revision))
            .createSync(recursive: true);
        await expectLater(
          runWithOverrides(
            () => shorebirdFlutter.useRevision(revision: revision),
          ),
          completes,
        );
        verifyNever(
          () => git.clone(
            url: ShorebirdFlutter.flutterGitUrl,
            outputDirectory: p.join(
              flutterDirectory.parent.path,
              revision,
            ),
            args: ['--filter=tree:0', '--no-checkout'],
          ),
        );
        verify(() => shorebirdEnv.flutterRevision = revision).called(1);
      });
    });

    group('useVersion', () {
      const version = '3.10.0';
      const newRevision = 'new-revision';

      setUp(() {
        when(
          () => git.revParse(
            revision: any(named: 'revision'),
            directory: any(named: 'directory'),
          ),
        ).thenAnswer((_) async => newRevision);
      });

      test('installs revision if it does not exist', () async {
        await expectLater(
          runWithOverrides(
            () => shorebirdFlutter.useVersion(version: version),
          ),
          completes,
        );
        verify(
          () => git.revParse(
            revision: 'origin/flutter_release/$version',
            directory: p.join(flutterDirectory.parent.path, flutterRevision),
          ),
        ).called(1);
        verify(
          () => git.clone(
            url: ShorebirdFlutter.flutterGitUrl,
            outputDirectory: p.join(
              flutterDirectory.parent.path,
              newRevision,
            ),
            args: ['--filter=tree:0', '--no-checkout'],
          ),
        ).called(1);
        verify(() => shorebirdEnv.flutterRevision = newRevision).called(1);
      });

      test('skips installation if revision already exists', () async {
        Directory(p.join(flutterDirectory.parent.path, newRevision))
            .createSync(recursive: true);
        await expectLater(
          runWithOverrides(
            () => shorebirdFlutter.useVersion(version: version),
          ),
          completes,
        );
        verify(
          () => git.revParse(
            revision: 'origin/flutter_release/$version',
            directory: p.join(flutterDirectory.parent.path, flutterRevision),
          ),
        ).called(1);
        verifyNever(
          () => git.clone(
            url: ShorebirdFlutter.flutterGitUrl,
            outputDirectory: p.join(
              flutterDirectory.parent.path,
              newRevision,
            ),
            args: ['--filter=tree:0', '--no-checkout'],
          ),
        );
        verify(() => shorebirdEnv.flutterRevision = newRevision).called(1);
      });
    });
  });
}

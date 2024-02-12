import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
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
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess process;
    late ShorebirdProcessResult processResult;
    late ShorebirdFlutter shorebirdFlutter;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          gitRef.overrideWith(() => git),
          processRef.overrideWith(() => process),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      shorebirdRoot = Directory.systemTemp.createTempSync();
      flutterDirectory = Directory(p.join(shorebirdRoot.path, 'flutter'));
      git = MockGit();
      shorebirdEnv = MockShorebirdEnv();
      process = MockShorebirdProcess();
      processResult = MockShorebirdProcessResult();
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
      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(
        () => process.run(
          'flutter',
          ['--version'],
          runInShell: true,
          useVendedFlutter: false,
        ),
      ).thenAnswer((_) async => processResult);
      when(() => processResult.exitCode).thenReturn(0);
    });

    group('getSystemVersion', () {
      test('throws ProcessException when process exits with non-zero code',
          () async {
        const error = 'oops';
        when(() => processResult.exitCode).thenReturn(ExitCode.software.code);
        when(() => processResult.stderr).thenReturn(error);
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
        when(() => processResult.stdout).thenReturn('');
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
        when(() => processResult.stdout).thenReturn('''
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
      });

      test('completes when clone and checkout succeed', () async {
        await expectLater(
          runWithOverrides(
            () => shorebirdFlutter.installRevision(revision: revision),
          ),
          completes,
        );
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

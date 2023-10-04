import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(ShorebirdVersion, () {
    const currentShorebirdRevision = 'revision-1';
    const newerShorebirdRevision = 'revision-2';

    late Git git;
    late ShorebirdVersion shorebirdVersionManager;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          gitRef.overrideWith(() => git),
        },
      );
    }

    setUp(() {
      git = MockGit();
      shorebirdVersionManager = ShorebirdVersion();

      when(
        () => git.fetch(
          directory: any(named: 'directory'),
          args: any(named: 'args'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => git.revParse(
          revision: any(named: 'revision'),
          directory: any(named: 'directory'),
        ),
      ).thenAnswer((_) async => currentShorebirdRevision);
      when(
        () => git.reset(
          revision: any(named: 'revision'),
          directory: any(named: 'directory'),
          args: any(named: 'args'),
        ),
      ).thenAnswer((_) async {});
    });

    group('isShorebirdVersionCurrent', () {
      test('returns true if current and latest git hashes match', () async {
        expect(
          await runWithOverrides(
            shorebirdVersionManager.isLatest,
          ),
          isTrue,
        );
        verify(
          () => git.fetch(directory: any(named: 'directory'), args: ['--tags']),
        ).called(1);
        verify(
          () => git.revParse(
            revision: 'HEAD',
            directory: any(named: 'directory'),
          ),
        ).called(1);
        verify(
          () => git.revParse(
            revision: '@{upstream}',
            directory: any(named: 'directory'),
          ),
        ).called(1);
      });

      test('returns false if current and latest git hashes differ', () async {
        when(
          () => git.revParse(
            revision: any(named: 'revision'),
            directory: any(named: 'directory'),
          ),
        ).thenAnswer((invocation) async {
          final revision = invocation.namedArguments[#revision] as String;
          if (revision == 'HEAD') {
            return currentShorebirdRevision;
          } else if (revision == '@{upstream}') {
            return newerShorebirdRevision;
          }
          throw UnsupportedError('Unexpected revision: $revision');
        });

        expect(
          await runWithOverrides(
            shorebirdVersionManager.isLatest,
          ),
          isFalse,
        );
        verify(
          () => git.fetch(directory: any(named: 'directory'), args: ['--tags']),
        ).called(1);
        verify(
          () => git.revParse(
            revision: 'HEAD',
            directory: any(named: 'directory'),
          ),
        ).called(1);
        verify(
          () => git.revParse(
            revision: '@{upstream}',
            directory: any(named: 'directory'),
          ),
        ).called(1);
      });

      test(
          'throws ProcessException if git command exits with code other than 0',
          () async {
        const errorMessage = 'oh no!';
        when(
          () => git.revParse(
            revision: any(named: 'revision'),
            directory: any(named: 'directory'),
          ),
        ).thenThrow(
          ProcessException(
            'git',
            ['rev-parse', 'HEAD'],
            errorMessage,
            ExitCode.software.code,
          ),
        );

        expect(
          runWithOverrides(
            shorebirdVersionManager.isLatest,
          ),
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

    group('attemptReset', () {
      test('completes when git command exits with code 0', () async {
        expect(
          runWithOverrides(
            () => shorebirdVersionManager.attemptReset(revision: 'HEAD'),
          ),
          completes,
        );
      });

      test('throws ProcessException when git command exits with non-zero code',
          () async {
        const errorMessage = 'oh no!';
        when(
          () => git.reset(
            revision: any(named: 'revision'),
            directory: any(named: 'directory'),
            args: any(named: 'args'),
          ),
        ).thenThrow(
          ProcessException(
            'git',
            ['reset', '--hard', 'HEAD'],
            errorMessage,
            ExitCode.software.code,
          ),
        );

        expect(
          runWithOverrides(
            () => shorebirdVersionManager.attemptReset(revision: 'HEAD'),
          ),
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
  });
}

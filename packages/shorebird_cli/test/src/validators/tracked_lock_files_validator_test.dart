import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/git.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(TrackedLockFilesValidator, () {
    late Git git;
    late ShorebirdEnv shorebirdEnv;
    late Directory projectRoot;

    late TrackedLockFilesValidator validator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          gitRef.overrideWith(() => git),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
    });

    setUp(() {
      git = MockGit();
      shorebirdEnv = MockShorebirdEnv();
      projectRoot = Directory.systemTemp.createTempSync();

      when(() => shorebirdEnv.getFlutterProjectRoot()).thenReturn(projectRoot);

      validator = TrackedLockFilesValidator();
    });

    test('has a non-empty description', () {
      expect(validator.description, isNotEmpty);
    });

    group('canRunInCurrentContext', () {
      group('when a pubspec.yaml file exists', () {
        setUp(() {
          when(() => shorebirdEnv.hasPubspecYaml).thenReturn(true);
        });

        test('returns true', () {
          expect(runWithOverrides(validator.canRunInCurrentContext), isTrue);
        });
      });

      group('when a pubspec.yaml file does not exist', () {
        setUp(() {
          when(() => shorebirdEnv.hasPubspecYaml).thenReturn(false);
        });

        test('returns false', () {
          expect(runWithOverrides(validator.canRunInCurrentContext), isFalse);
        });
      });
    });

    group('validate', () {
      group('when no project root is found', () {
        setUp(() {
          when(() => shorebirdEnv.getFlutterProjectRoot()).thenReturn(null);
        });

        test('returns an empty list', () async {
          final issues = await runWithOverrides(() => validator.validate());
          expect(issues, isEmpty);
        });
      });

      group('when project is not tracked in git', () {
        setUp(() {
          when(
            () => git.isGitRepo(directory: any(named: 'directory')),
          ).thenAnswer((_) async => false);
        });

        test('returns no issues', () async {
          final issues = await runWithOverrides(() => validator.validate());
          expect(issues, isEmpty);
        });
      });

      group('when a lock file does not exist', () {
        setUp(() {
          when(
            () => git.isGitRepo(directory: any(named: 'directory')),
          ).thenAnswer((_) async => true);
        });

        test('does not warn about lock file not being tracked', () async {
          final issues = await runWithOverrides(() => validator.validate());
          expect(issues, isEmpty);
        });
      });

      group('when a lock file exists but is not tracked', () {
        setUp(() {
          when(
            () => git.isGitRepo(directory: any(named: 'directory')),
          ).thenAnswer((_) async => true);
          when(
            () => git.isFileTracked(file: any(named: 'file')),
          ).thenAnswer((_) async => false);

          File(p.join(projectRoot.path, 'pubspec.lock')).createSync();
        });

        test('recommends adding lock file to source control', () async {
          final issues = await runWithOverrides(() => validator.validate());
          expect(issues, hasLength(1));
          expect(
            issues.first,
            equals(
              ValidationIssue.warning(
                message:
                    '''pubspec.lock is not tracked in source control. We recommend tracking lock files in source control to avoid unexpected dependency version changes.''',
              ),
            ),
          );
        });
      });

      group('when lock file exists and is tracked', () {
        setUp(() {
          when(
            () => git.isGitRepo(directory: any(named: 'directory')),
          ).thenAnswer((_) async => true);
          when(
            () => git.isFileTracked(file: any(named: 'file')),
          ).thenAnswer((_) async => true);

          File(p.join(projectRoot.path, 'pubspec.lock')).createSync();
        });

        test('returns no issues', () async {
          final issues = await runWithOverrides(() => validator.validate());
          expect(issues, isEmpty);
        });
      });
    });
  });
}

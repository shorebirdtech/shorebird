import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/git.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter_manager.dart';
import 'package:test/test.dart';

class _MockGit extends Mock implements Git {}

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

void main() {
  group(ShorebirdFlutterManager, () {
    late Directory shorebirdRoot;
    late Directory flutterDirectory;
    late Git git;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutterManager shorebirdFlutterManager;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          gitRef.overrideWith(() => git),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      shorebirdRoot = Directory.systemTemp.createTempSync();
      flutterDirectory = Directory(p.join(shorebirdRoot.path, 'flutter'));
      git = _MockGit();
      shorebirdEnv = _MockShorebirdEnv();
      shorebirdFlutterManager = runWithOverrides(ShorebirdFlutterManager.new);

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
      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
    });

    group('installRevision', () {
      const revision = 'test-revision';
      test('does nothing if the revision is already installed', () async {
        Directory(
          p.join(flutterDirectory.parent.path, revision),
        ).createSync(recursive: true);

        await runWithOverrides(
          () => shorebirdFlutterManager.installRevision(revision: revision),
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
            () => shorebirdFlutterManager.installRevision(revision: revision),
          ),
          throwsA(exception),
        );

        verify(
          () => git.clone(
            url: ShorebirdFlutterManager.flutterGitUrl,
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
            () => shorebirdFlutterManager.installRevision(revision: revision),
          ),
          throwsA(exception),
        );
        verify(
          () => git.clone(
            url: ShorebirdFlutterManager.flutterGitUrl,
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
            () => shorebirdFlutterManager.installRevision(revision: revision),
          ),
          completes,
        );
      });
    });
  });
}

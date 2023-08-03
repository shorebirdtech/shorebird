import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter_manager.dart';
import 'package:test/test.dart';

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockShorebirdProcessResult extends Mock
    implements ShorebirdProcessResult {}

void main() {
  group(ShorebirdFlutterManager, () {
    late Directory shorebirdRoot;
    late Directory flutterDirectory;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcessResult cloneProcessResult;
    late ShorebirdProcessResult checkoutProcessResult;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdFlutterManager shorebirdFlutterManager;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      shorebirdRoot = Directory.systemTemp.createTempSync();
      flutterDirectory = Directory(p.join(shorebirdRoot.path, 'flutter'));
      shorebirdEnv = _MockShorebirdEnv();
      cloneProcessResult = _MockShorebirdProcessResult();
      checkoutProcessResult = _MockShorebirdProcessResult();
      shorebirdProcess = _MockShorebirdProcess();
      shorebirdFlutterManager = runWithOverrides(ShorebirdFlutterManager.new);

      when(() => shorebirdEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(
        () => shorebirdProcess.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((invocation) async {
        final executable = invocation.positionalArguments[0] as String;
        final args = invocation.positionalArguments[1] as List<String>;
        if (executable == 'git' && args[0] == 'clone') {
          return cloneProcessResult;
        } else if (executable == 'git' && args[4] == 'checkout') {
          return checkoutProcessResult;
        } else {
          throw UnimplementedError();
        }
      });
      when(() => cloneProcessResult.exitCode).thenReturn(ExitCode.success.code);
      when(
        () => checkoutProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
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

        verifyNever(() => shorebirdProcess.run(any(), any()));
      });

      test('throws ProcessException if unable to clone', () async {
        when(
          () => cloneProcessResult.exitCode,
        ).thenReturn(ExitCode.software.code);

        await expectLater(
          runWithOverrides(
            () => shorebirdFlutterManager.installRevision(revision: revision),
          ),
          throwsA(isA<ProcessException>()),
        );

        verify(
          () => shorebirdProcess.run(
            'git',
            [
              'clone',
              '--filter=tree:0',
              ShorebirdFlutterManager.flutterGitUrl,
              '--no-checkout',
              p.join(flutterDirectory.parent.path, revision)
            ],
            runInShell: true,
          ),
        ).called(1);
      });

      test('throws ProcessException if unable to checkout revision', () async {
        when(
          () => checkoutProcessResult.exitCode,
        ).thenReturn(ExitCode.software.code);

        await expectLater(
          runWithOverrides(
            () => shorebirdFlutterManager.installRevision(revision: revision),
          ),
          throwsA(isA<ProcessException>()),
        );

        verify(
          () => shorebirdProcess.run(
            'git',
            [
              'clone',
              '--filter=tree:0',
              ShorebirdFlutterManager.flutterGitUrl,
              '--no-checkout',
              p.join(flutterDirectory.parent.path, revision)
            ],
            runInShell: true,
          ),
        ).called(1);
        verify(
          () => shorebirdProcess.run(
            'git',
            [
              '-C',
              p.join(flutterDirectory.parent.path, revision),
              '-c',
              'advice.detachedHead=false',
              'checkout',
              revision,
            ],
            runInShell: true,
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

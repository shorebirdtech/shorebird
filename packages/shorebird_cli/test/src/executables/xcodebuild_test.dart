import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(XcodeBuild, () {
    late ShorebirdProcess process;
    late ShorebirdProcessResult processResult;
    late XcodeBuild xcodeBuild;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          processRef.overrideWith(() => process),
        },
      );
    }

    Directory setUpAppTempDir() {
      final tempDir = Directory.systemTemp.createTempSync();
      Directory(p.join(tempDir.path, 'ios')).createSync(recursive: true);
      return tempDir;
    }

    setUp(() {
      process = MockShorebirdProcess();
      processResult = MockShorebirdProcessResult();
      xcodeBuild = runWithOverrides(XcodeBuild.new);
    });

    group(MissingIOSProjectException, () {
      test('toString', () {
        const exception = MissingIOSProjectException('test_project_path');
        expect(
          exception.toString(),
          '''
Could not find an iOS project in test_project_path.
To add iOS, run "flutter create . --platforms ios"''',
        );
      });
    });

    group('list', () {
      test('throws a MissingIOSProjectException if no iOS project is found',
          () {
        final tempDir = Directory.systemTemp.createTempSync();
        expect(
          () => xcodeBuild.list(tempDir.path),
          throwsA(isA<MissingIOSProjectException>()),
        );
        verifyNever(
          () => process.run(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        );
      });

      test('throws ProcessException when xcodebuild fails', () async {
        final tempDir = setUpAppTempDir();
        const message = 'oops';
        when(
          () => process.run(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async => ShorebirdProcessResult(
            exitCode: ExitCode.software.code,
            stdout: '',
            stderr: message,
          ),
        );
        expect(
          () => runWithOverrides(() => xcodeBuild.list(tempDir.path)),
          throwsA(isA<ProcessException>()),
        );
      });

      test('returns correct XcodeProjectBuildInfo for an app', () async {
        final tempDir = setUpAppTempDir();
        when(
          () => process.run(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async => ShorebirdProcessResult(
            exitCode: ExitCode.success.code,
            stdout: File(p.join('test', 'fixtures', 'xcodebuild_list.txt'))
                .readAsStringSync(),
            stderr: '',
          ),
        );
        final info = await runWithOverrides(
          () => xcodeBuild.list(tempDir.path),
        );
        expect(info.targets, equals({'Runner', 'RunnerTests'}));
        expect(
          info.buildConfigurations,
          equals(
            {
              'Debug',
              'Debug-stable',
              'Debug-internal',
              'Release',
              'Release-stable',
              'Release-internal',
              'Profile',
              'Profile-stable',
              'Profile-internal',
            },
          ),
        );
        expect(info.schemes, equals({'Runner', 'stable', 'internal'}));
        verify(
          () => process.run(
            'xcodebuild',
            ['-list'],
            workingDirectory: p.join(tempDir.path, 'ios'),
          ),
        ).called(1);
      });
    });

    group('xcodeVersion', () {
      late ExitCode exitCode;
      late String stdout;

      setUp(() {
        when(() => process.run(XcodeBuild.executable, ['-version']))
            .thenAnswer((_) async => processResult);
        when(() => processResult.exitCode).thenAnswer((_) => exitCode.code);
        when(() => processResult.stdout).thenAnswer((_) => stdout);
      });

      group('when a non-zero exit code is returned', () {
        const errorMessage = 'An unexpected error occurred.';
        setUp(() {
          stdout = '';
          exitCode = ExitCode.cantCreate;
          when(() => processResult.stderr).thenReturn(errorMessage);
        });

        test('throws a ProcessException', () async {
          expect(
            () => runWithOverrides(xcodeBuild.xcodeVersion),
            throwsA(
              isA<ProcessException>()
                  .having((e) => e.message, 'message', errorMessage),
            ),
          );
        });
      });

      group('when stdout contains unexpected output', () {
        setUp(() {
          exitCode = ExitCode.success;
        });

        test('reutrns null if output is empty', () async {
          stdout = '';
          expect(
            await runWithOverrides(xcodeBuild.xcodeVersion),
            isNull,
          );
        });

        test('returns null if output does not contain version', () async {
          stdout = 'unexpected output';
          expect(
            await runWithOverrides(xcodeBuild.xcodeVersion),
            isNull,
          );
        });
      });

      group('when stdout contains valid output', () {
        setUp(() {
          exitCode = ExitCode.success;
        });

        test('returns correct version with major, minor, and build numbers',
            () async {
          stdout = '''
Xcode 14.3.1
Build version 14E300c
''';
          final version = await runWithOverrides(xcodeBuild.xcodeVersion);
          expect(version, Version(14, 3, 1));
        });

        test('returns correct version with only major and minor numbers',
            () async {
          stdout = '''
Xcode 15.0
Build version 15A240d
''';
          final version = await runWithOverrides(xcodeBuild.xcodeVersion);
          expect(version, Version(15, 0, 0));
        });
      });
    });
  });
}

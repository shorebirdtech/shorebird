import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/xcodebuild.dart';
import 'package:test/test.dart';

class _MockProcess extends Mock implements ShorebirdProcess {}

void main() {
  group(XcodeBuild, () {
    late ShorebirdProcess process;
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
      process = _MockProcess();
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
              'Profile-internal'
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
  });
}

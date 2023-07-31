import 'dart:io' hide Platform;

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/gradlew.dart';
import 'package:shorebird_cli/src/java.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:test/test.dart';

class _MockJava extends Mock implements Java {}

class _MockPlatform extends Mock implements Platform {}

class _MockProcess extends Mock implements ShorebirdProcess {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

void main() {
  group(Gradlew, () {
    const javaHome = 'test_java_home';

    late Java java;
    late Platform platform;
    late ShorebirdProcess process;
    late ShorebirdProcessResult result;
    late Gradlew gradlew;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          javaRef.overrideWith(() => java),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => process),
        },
      );
    }

    setUp(() {
      java = _MockJava();
      platform = _MockPlatform();
      process = _MockProcess();
      result = _MockProcessResult();
      gradlew = runWithOverrides(Gradlew.new);

      when(() => java.home).thenReturn(javaHome);
      when(
        () => process.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async => result);
      when(() => result.exitCode).thenReturn(ExitCode.success.code);
      when(() => result.stdout).thenReturn('');
    });

    group(MissingGradleWrapperException, () {
      test('toString is correct', () {
        expect(
          const MissingGradleWrapperException('test').toString(),
          '''
Could not find test.
Make sure you have run "flutter build apk" at least once.''',
        );
      });
    });

    group('productFlavors', () {
      Directory setUpAppTempDir() {
        final tempDir = Directory.systemTemp.createTempSync();
        Directory(p.join(tempDir.path, 'android')).createSync(recursive: true);
        return tempDir;
      }

      Directory setUpModuleTempDir() {
        final tempDir = Directory.systemTemp.createTempSync();
        Directory(p.join(tempDir.path, '.android')).createSync(recursive: true);
        return tempDir;
      }

      test(
          'throws MissingGradleWrapperException '
          'when android root does not exist', () async {
        when(() => platform.isLinux).thenReturn(true);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isWindows).thenReturn(false);
        final tempDir = Directory.systemTemp.createTempSync();
        await expectLater(
          runWithOverrides(() => gradlew.productFlavors(tempDir.path)),
          throwsA(isA<MissingGradleWrapperException>()),
        );
        verifyNever(
          () => process.run(
            p.join(tempDir.path, 'android', 'gradlew'),
            ['app:tasks', '--all', '--console=auto'],
            runInShell: true,
            workingDirectory: p.join(tempDir.path, 'android'),
            environment: {'JAVA_HOME': javaHome},
          ),
        );
      });

      test(
          'throws MissingGradleWrapperException '
          'when gradlew does not exist', () async {
        when(() => platform.isLinux).thenReturn(true);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isWindows).thenReturn(false);
        final tempDir = setUpAppTempDir();
        await expectLater(
          runWithOverrides(() => gradlew.productFlavors(tempDir.path)),
          throwsA(isA<MissingGradleWrapperException>()),
        );
        verifyNever(
          () => process.run(
            p.join(tempDir.path, 'android', 'gradlew'),
            ['app:tasks', '--all', '--console=auto'],
            runInShell: true,
            workingDirectory: p.join(tempDir.path, 'android'),
            environment: {'JAVA_HOME': javaHome},
          ),
        );
      });

      test('uses existing JAVA_HOME when set', () async {
        when(() => platform.isLinux).thenReturn(true);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isWindows).thenReturn(false);
        final tempDir = setUpAppTempDir();
        File(
          p.join(tempDir.path, 'android', 'gradlew'),
        ).createSync(recursive: true);
        await expectLater(
          runWithOverrides(() => gradlew.productFlavors(tempDir.path)),
          completes,
        );
        verify(
          () => process.run(
            p.join(tempDir.path, 'android', 'gradlew'),
            ['app:tasks', '--all', '--console=auto'],
            runInShell: true,
            workingDirectory: p.join(tempDir.path, 'android'),
            environment: {'JAVA_HOME': javaHome},
          ),
        ).called(1);
      });

      test(
          'throws Exception '
          'when process exits with non-zero code', () async {
        when(() => platform.isLinux).thenReturn(true);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isWindows).thenReturn(false);
        final tempDir = setUpAppTempDir();
        File(
          p.join(tempDir.path, 'android', 'gradlew'),
        ).createSync(recursive: true);
        when(() => result.exitCode).thenReturn(1);
        when(() => result.stderr).thenReturn('test error');
        await expectLater(
          runWithOverrides(() => gradlew.productFlavors(tempDir.path)),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'message',
              contains('test error'),
            ),
          ),
        );
        verify(
          () => process.run(
            p.join(tempDir.path, 'android', 'gradlew'),
            ['app:tasks', '--all', '--console=auto'],
            runInShell: true,
            workingDirectory: p.join(tempDir.path, 'android'),
            environment: {'JAVA_HOME': javaHome},
          ),
        ).called(1);
      });

      test('extracts flavors', () async {
        when(() => platform.isLinux).thenReturn(true);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isWindows).thenReturn(false);
        final tempDir = setUpModuleTempDir();
        File(
          p.join(tempDir.path, '.android', 'gradlew'),
        ).createSync(recursive: true);
        const javaHome = 'test_java_home';
        when(() => platform.environment).thenReturn({'JAVA_HOME': javaHome});
        when(() => result.stdout).thenReturn(
          File(
            p.join('test', 'fixtures', 'gradle_app_tasks.txt'),
          ).readAsStringSync(),
        );
        await expectLater(
          runWithOverrides(() => gradlew.productFlavors(tempDir.path)),
          completion(
            equals({
              'development',
              'developmentInternal',
              'staging',
              'stagingInternal',
              'production',
              'productionInternal',
            }),
          ),
        );
        verify(
          () => process.run(
            p.join(tempDir.path, '.android', 'gradlew'),
            ['app:tasks', '--all', '--console=auto'],
            runInShell: true,
            workingDirectory: p.join(tempDir.path, '.android'),
            environment: {'JAVA_HOME': javaHome},
          ),
        ).called(1);
      });

      test('extracts flavors from module directory structure', () async {
        when(() => platform.isLinux).thenReturn(true);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isWindows).thenReturn(false);
        final tempDir = setUpModuleTempDir();
        File(
          p.join(tempDir.path, '.android', 'gradlew'),
        ).createSync(recursive: true);
        const javaHome = 'test_java_home';
        when(() => platform.environment).thenReturn({'JAVA_HOME': javaHome});
        await expectLater(
          runWithOverrides(() => gradlew.productFlavors(tempDir.path)),
          completes,
        );
        verify(
          () => process.run(
            p.join(tempDir.path, '.android', 'gradlew'),
            ['app:tasks', '--all', '--console=auto'],
            runInShell: true,
            workingDirectory: p.join(tempDir.path, '.android'),
            environment: {'JAVA_HOME': javaHome},
          ),
        ).called(1);
      });
    });
  });
}

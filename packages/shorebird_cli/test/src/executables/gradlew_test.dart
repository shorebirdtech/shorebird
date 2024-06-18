import 'dart:io' hide Platform;

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(Gradlew, () {
    const javaHome = 'test_java_home';

    late Java java;
    late ShorebirdProcess process;
    late ShorebirdProcessResult result;
    late Gradlew gradlew;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          javaRef.overrideWith(() => java),
          processRef.overrideWith(() => process),
        },
      );
    }

    setUp(() {
      java = MockJava();
      process = MockShorebirdProcess();
      result = MockProcessResult();
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

    group(MissingAndroidProjectException, () {
      test('toString is correct', () {
        expect(
          const MissingAndroidProjectException('test').toString(),
          '''
Could not find an android project in test.
To add android, run "flutter create . --platforms android"''',
        );
      });
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

    Directory setUpAppTempDir() {
      final tempDir = Directory.systemTemp.createTempSync();
      Directory(p.join(tempDir.path, 'android')).createSync(recursive: true);
      return tempDir;
    }

    group('productFlavors', () {
      test(
        'throws MissingAndroidProjectException '
        'when android root does not exist',
        () async {
          final tempDir = Directory.systemTemp.createTempSync();
          await expectLater(
            runWithOverrides(() => gradlew.productFlavors(tempDir.path)),
            throwsA(isA<MissingAndroidProjectException>()),
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
        },
        testOn: 'linux',
      );

      test(
        'throws MissingGradleWrapperException '
        'when gradlew does not exist',
        () async {
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
        },
        testOn: 'linux',
      );

      test(
        'uses existing JAVA_HOME when set',
        () async {
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
        },
        testOn: 'linux',
      );

      test(
        'throws Exception '
        'when process exits with non-zero code',
        () async {
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
        },
        testOn: 'linux',
      );

      test(
        'extracts flavors',
        () async {
          final tempDir = setUpAppTempDir();
          File(
            p.join(tempDir.path, 'android', 'gradlew'),
          ).createSync(recursive: true);
          const javaHome = 'test_java_home';
          when(() => result.stdout).thenReturn(
            File(
              p.join('test', 'fixtures', 'gradle', 'gradle_app_tasks.txt'),
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
              p.join(tempDir.path, 'android', 'gradlew'),
              ['app:tasks', '--all', '--console=auto'],
              runInShell: true,
              workingDirectory: p.join(tempDir.path, 'android'),
              environment: {'JAVA_HOME': javaHome},
            ),
          ).called(1);
        },
        testOn: 'linux',
      );

      group('when flavors are all upper case', () {
        test(
          'extracts flavors',
          () async {
            final tempDir = setUpAppTempDir();
            File(
              p.join(tempDir.path, 'android', 'gradlew'),
            ).createSync(recursive: true);
            when(() => result.stdout).thenReturn(
              File(
                p.join(
                  'test',
                  'fixtures',
                  'gradle',
                  'gradle_app_tasks_upper_case_flavors.txt',
                ),
              ).readAsStringSync(),
            );
            await expectLater(
              runWithOverrides(() => gradlew.productFlavors(tempDir.path)),
              completion(
                equals({
                  'SP',
                  'RJ',
                }),
              ),
            );
          },
          testOn: 'linux',
        );
      });

      group(
        'when flavors are mixed, starting with upper case, finishin with camel',
        () {
          test(
            'extracts flavors',
            () async {
              final tempDir = setUpAppTempDir();
              File(
                p.join(tempDir.path, 'android', 'gradlew'),
              ).createSync(recursive: true);
              when(() => result.stdout).thenReturn(
                File(
                  p.join(
                    'test',
                    'fixtures',
                    'gradle',
                    'gradle_app_tasks_mixed_case_flavors.txt',
                  ),
                ).readAsStringSync(),
              );
              await expectLater(
                runWithOverrides(() => gradlew.productFlavors(tempDir.path)),
                completion(
                  equals({
                    'SPaulo',
                    'RJaneiro',
                  }),
                ),
              );
            },
            testOn: 'linux',
          );
        },
      );

      group(
        'when flavors starts with upper case, finishing with numbers',
        () {
          test(
            'extracts flavors',
            () async {
              final tempDir = setUpAppTempDir();
              File(
                p.join(tempDir.path, 'android', 'gradlew'),
              ).createSync(recursive: true);
              when(() => result.stdout).thenReturn(
                File(
                  p.join(
                    'test',
                    'fixtures',
                    'gradle',
                    'gradle_app_tasks_numbers_upper_case_flavors.txt',
                  ),
                ).readAsStringSync(),
              );
              await expectLater(
                runWithOverrides(() => gradlew.productFlavors(tempDir.path)),
                completion(
                  equals({
                    'CB500',
                    'NX700',
                  }),
                ),
              );
            },
            testOn: 'linux',
          );
        },
      );
    });

    group('exists', () {
      late Directory tempDir;
      setUp(() {
        tempDir = setUpAppTempDir();
      });

      group('when gradlew does not exist', () {
        test('returns false', () {
          expect(gradlew.exists(tempDir.path), isFalse);
        });
      });

      group('when gradlew exists', () {
        group(
          'when on unix based OSs',
          () {
            setUp(() {
              File(
                p.join(tempDir.path, 'android', 'gradlew'),
              ).createSync(recursive: true);
            });

            test(
              'returns true',
              () {
                expect(gradlew.exists(tempDir.path), isTrue);
              },
              testOn: 'linux || mac-os',
            );
          },
        );

        group(
          'when on windows',
          () {
            setUp(() {
              File(
                p.join(tempDir.path, 'android', 'gradlew.bat'),
              ).createSync(recursive: true);
            });

            test(
              'returns true',
              () {
                expect(gradlew.exists(tempDir.path), isTrue);
              },
              testOn: 'windows',
            );
          },
        );
      });
    });

    group('version', () {
      late Directory tempDir;

      setUp(() {
        tempDir = setUpAppTempDir();
        File(
          p.join(tempDir.path, 'android', 'gradlew'),
        ).createSync(recursive: true);
        when(() => result.stdout).thenReturn('''

------------------------------------------------------------
Gradle 7.6.3
------------------------------------------------------------

Build time:   2023-10-04 15:59:47 UTC
Revision:     1694251d59e0d4752d547e1fd5b5020b798a7e71

Kotlin:       1.7.10
Groovy:       3.0.13
Ant:          Apache Ant(TM) version 1.10.11 compiled on July 10 2021
JVM:          11.0.23 (Azul Systems, Inc. 11.0.23+9-LTS)
OS:           Mac OS X 14.4.1 aarch64
''');
      });

      test(
        'returns the correct version',
        () async {
          final version = await runWithOverrides(
            () => gradlew.version(tempDir.path),
          );
          expect(version, '7.6.3');
        },
        testOn: 'linux || mac-os',
      );

      group('when the output cannot be parsed', () {
        setUp(() {
          when(() => result.stdout).thenReturn('not a real version');
        });

        test(
          'returns unknown',
          () async {
            final version = await runWithOverrides(
              () => gradlew.version(tempDir.path),
            );
            expect(version, 'unknown');
          },
          testOn: 'linux || mac-os',
        );
      });
    });
  });
}

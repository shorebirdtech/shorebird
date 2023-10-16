import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/os/os.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(Java, () {
    late AndroidStudio androidStudio;
    late OperatingSystemInterface osInterface;
    late Platform platform;
    late Java java;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          androidStudioRef.overrideWith(() => androidStudio),
          osInterfaceRef.overrideWith(() => osInterface),
          platformRef.overrideWith(() => platform),
        },
      );
    }

    Directory setUpAppTempDir() {
      final tempDir = Directory.systemTemp.createTempSync();
      Directory(p.join(tempDir.path, 'android')).createSync(recursive: true);
      return tempDir;
    }

    setUp(() {
      androidStudio = MockAndroidStudio();
      osInterface = MockOperatingSystemInterface();
      platform = MockPlatform();
      java = Java();

      when(() => platform.environment).thenReturn({});
      when(() => platform.isWindows).thenReturn(false);
      when(() => platform.isMacOS).thenReturn(false);
      when(() => platform.isLinux).thenReturn(false);

      when(() => osInterface.which(any())).thenReturn(null);
    });

    group('executable', () {
      group('when on Windows', () {
        const javaHome = r'C:\Program Files\Java\jdk-11.0.1';

        setUp(() {
          when(() => platform.isWindows).thenReturn(true);
          when(() => platform.environment).thenReturn({'JAVA_HOME': javaHome});
        });

        test('returns correct executable on windows', () async {
          expect(
            runWithOverrides(() => java.executable),
            equals(p.join(javaHome, 'bin', 'java.exe')),
          );
        });
      });

      group('when on a non-Windows OS', () {
        setUp(() {
          when(() => platform.isWindows).thenReturn(false);
        });

        test('returns correct executable on non-windows', () async {
          expect(
            runWithOverrides(() => java.executable),
            equals('java'),
          );
        });
      });
    });

    group('home', () {
      group('when Android Studio is installed', () {
        late Directory jbrDir;

        group('when on macOS', () {
          setUp(() {
            when(() => platform.isMacOS).thenReturn(true);

            final tempDir = setUpAppTempDir();
            final androidStudioDir = Directory(
              p.join(
                tempDir.path,
                'Applications',
                'Android Studio.app',
                'Contents',
              ),
            )..createSync(recursive: true);
            when(() => androidStudio.path).thenReturn(androidStudioDir.path);
            jbrDir = Directory(
              p.join(androidStudioDir.path, 'jbr', 'Contents', 'Home'),
            )..createSync(recursive: true);
            File(
              p.join(tempDir.path, 'android', 'gradlew'),
            ).createSync(recursive: true);
            when(() => platform.environment).thenReturn({'HOME': tempDir.path});
          });

          test('returns correct path', () async {
            await expectLater(
              runWithOverrides(() => java.home),
              equals(jbrDir.path),
            );
          });

          test('does not check JAVA_HOME or PATH', () {
            runWithOverrides(() => java.home);

            verifyNever(() => osInterface.which(any()));
            verifyNever(() => platform.environment);
          });
        });

        group('when on Windows', () {
          late Directory jbrDir;

          setUp(() {
            when(() => platform.isWindows).thenReturn(true);

            final tempDir = setUpAppTempDir();
            final androidStudioDir = Directory(
              p.join(tempDir.path, 'Android', 'Android Studio'),
            )..createSync(recursive: true);
            when(() => androidStudio.path).thenReturn(androidStudioDir.path);
            jbrDir = Directory(p.join(androidStudioDir.path, 'jbr'))
              ..createSync();
            File(
              p.join(tempDir.path, 'android', 'gradlew.bat'),
            ).createSync(recursive: true);
            when(() => platform.environment).thenReturn({
              'PROGRAMFILES': tempDir.path,
              'PROGRAMFILES(X86)': tempDir.path,
            });
          });

          test('returns correct path', () async {
            await expectLater(
              runWithOverrides(() => java.home),
              equals(jbrDir.path),
            );
          });

          test('does not check JAVA_HOME or PATH', () {
            runWithOverrides(() => java.home);

            verifyNever(() => osInterface.which(any()));
            verifyNever(() => platform.environment);
          });
        });

        group('when on Linux', () {
          setUp(() {
            when(() => platform.isLinux).thenReturn(true);

            final tempDir = setUpAppTempDir();
            final androidStudioDir = Directory(
              p.join(tempDir.path, '.AndroidStudio'),
            )..createSync(recursive: true);
            when(() => androidStudio.path).thenReturn(androidStudioDir.path);
            jbrDir = Directory(p.join(androidStudioDir.path, 'jbr'))
              ..createSync(recursive: true);
            File(
              p.join(tempDir.path, 'android', 'gradlew'),
            ).createSync(recursive: true);

            when(() => platform.environment).thenReturn({'HOME': tempDir.path});
          });

          test('returns correct path', () async {
            await expectLater(
              runWithOverrides(() => java.home),
              equals(jbrDir.path),
            );
          });
        });
      });

      group('when Android Studio is not installed', () {
        group('when JAVA_HOME is set', () {
          const javaHome = r'C:\Program Files\Java\jdk-11.0.1';
          setUp(() {
            when(() => platform.environment)
                .thenReturn({'JAVA_HOME': javaHome});
          });

          test('returns value of JAVA_HOME', () {
            expect(
              runWithOverrides(() => java.home),
              equals(javaHome),
            );
          });

          test('does not check PATH', () {
            runWithOverrides(() => java.home);

            verifyNever(() => osInterface.which(any()));
          });
        });

        group('when JAVA_HOME is not set', () {
          group("when java is on the user's path", () {
            const javaPath = '/path/to/java';
            setUp(() {
              when(() => osInterface.which('java')).thenReturn(javaPath);
            });

            test('returns path to java', () {
              expect(
                runWithOverrides(() => java.home),
                equals('/path/to/java'),
              );
            });
          });

          group("when java is not on the user's path", () {
            setUp(() {
              when(() => osInterface.which('java')).thenReturn(null);
            });

            test('returns null', () {
              expect(runWithOverrides(() => java.home), isNull);
            });
          });
        });
      });
    });
  });
}

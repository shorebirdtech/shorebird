import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/java.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:test/test.dart';

class _MockAndroidStudio extends Mock implements AndroidStudio {}

class _MockPlatform extends Mock implements Platform {}

void main() {
  group(Java, () {
    late AndroidStudio androidStudio;
    late Platform platform;
    late Java java;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          androidStudioRef.overrideWith(() => androidStudio),
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
      androidStudio = _MockAndroidStudio();
      platform = _MockPlatform();
      java = Java();
    });

    group('executable', () {
      test('returns correct executable on windows', () async {
        const javaHome = r'C:\Program Files\Java\jdk-11.0.1';
        when(() => platform.isWindows).thenReturn(true);
        when(() => platform.environment).thenReturn({'JAVA_HOME': javaHome});
        expect(
          runWithOverrides(() => java.executable),
          equals(p.join(javaHome, 'bin', 'java.exe')),
        );
      });

      test('returns correct executable on non-windows', () async {
        when(() => platform.isWindows).thenReturn(false);
        expect(
          runWithOverrides(() => java.executable),
          equals('java'),
        );
      });
    });

    group('home', () {
      test('returns existing JAVA_HOME if already set', () async {
        const javaHome = r'C:\Program Files\Java\jdk-11.0.1';
        when(() => platform.environment).thenReturn({'JAVA_HOME': javaHome});
        expect(
          runWithOverrides(() => java.home),
          equals(javaHome),
        );
      });

      test(
          'returns null if JAVA_HOME is not set and'
          ' Android Studio is not installed', () async {
        when(() => platform.environment).thenReturn({});
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isWindows).thenReturn(false);
        when(() => platform.isLinux).thenReturn(false);
        expect(runWithOverrides(() => java.home), isNull);
      });

      test('returns correct path on windows', () async {
        final tempDir = setUpAppTempDir();
        final androidStudioDir = Directory(
          p.join(tempDir.path, 'Android', 'Android Studio'),
        )..createSync(recursive: true);
        when(() => androidStudio.path).thenReturn(androidStudioDir.path);
        final jbrDir = Directory(p.join(androidStudioDir.path, 'jbr'))
          ..createSync();
        File(
          p.join(tempDir.path, 'android', 'gradlew.bat'),
        ).createSync(recursive: true);
        when(() => platform.isWindows).thenReturn(true);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isLinux).thenReturn(false);
        when(() => platform.environment).thenReturn({
          'PROGRAMFILES': tempDir.path,
          'PROGRAMFILES(X86)': tempDir.path,
        });
        await expectLater(
            runWithOverrides(() => java.home), equals(jbrDir.path));
      });

      test('returns correct path on MacOS', () async {
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
        final jbrDir = Directory(
          p.join(androidStudioDir.path, 'jbr', 'Contents', 'Home'),
        )..createSync(recursive: true);
        File(
          p.join(tempDir.path, 'android', 'gradlew'),
        ).createSync(recursive: true);
        when(() => platform.isWindows).thenReturn(false);
        when(() => platform.isMacOS).thenReturn(true);
        when(() => platform.isLinux).thenReturn(false);
        when(() => platform.environment).thenReturn({'HOME': tempDir.path});
        await expectLater(
            runWithOverrides(() => java.home), equals(jbrDir.path));
      });

      test('returns correct path on Linux', () async {
        final tempDir = setUpAppTempDir();
        final androidStudioDir = Directory(
          p.join(tempDir.path, '.AndroidStudio'),
        )..createSync(recursive: true);
        when(() => androidStudio.path).thenReturn(androidStudioDir.path);
        final jbrDir = Directory(p.join(androidStudioDir.path, 'jbr'))
          ..createSync(recursive: true);
        File(
          p.join(tempDir.path, 'android', 'gradlew'),
        ).createSync(recursive: true);
        when(() => platform.isWindows).thenReturn(false);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isLinux).thenReturn(true);
        when(() => platform.environment).thenReturn({'HOME': tempDir.path});
        await expectLater(
            runWithOverrides(() => java.home), equals(jbrDir.path));
      });
    });
  });
}

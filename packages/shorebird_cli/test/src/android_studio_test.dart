import 'dart:io' hide Platform;

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(AndroidStudio, () {
    late Platform platform;
    late AndroidStudio androidStudio;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
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
      platform = MockPlatform();
      androidStudio = AndroidStudio();
    });

    group('path', () {
      test('returns correct path on windows', () async {
        final tempDir = setUpAppTempDir();
        final androidStudioDir = Directory(
          p.join(tempDir.path, 'Android', 'Android Studio'),
        )..createSync(recursive: true);
        when(() => platform.isWindows).thenReturn(true);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isLinux).thenReturn(false);
        when(() => platform.environment).thenReturn({
          'PROGRAMFILES': tempDir.path,
          'PROGRAMFILES(X86)': tempDir.path,
        });
        await expectLater(
          runWithOverrides(() => androidStudio.path),
          equals(androidStudioDir.path),
        );
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
        when(() => platform.isWindows).thenReturn(false);
        when(() => platform.isMacOS).thenReturn(true);
        when(() => platform.isLinux).thenReturn(false);
        when(() => platform.environment).thenReturn({'HOME': tempDir.path});
        await expectLater(
          runWithOverrides(() => androidStudio.path),
          equals(androidStudioDir.path),
        );
      });

      test('returns correct path on Linux', () async {
        final tempDir = setUpAppTempDir();
        final androidStudioDir = Directory(
          p.join(tempDir.path, '.AndroidStudio'),
        )..createSync(recursive: true);
        when(() => platform.isWindows).thenReturn(false);
        when(() => platform.isMacOS).thenReturn(false);
        when(() => platform.isLinux).thenReturn(true);
        when(() => platform.environment).thenReturn({'HOME': tempDir.path});
        await expectLater(
          runWithOverrides(() => androidStudio.path),
          equals(androidStudioDir.path),
        );
      });
    });
  });
}

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
      group('on Windows', () {
        setUp(() {
          when(() => platform.isWindows).thenReturn(true);
          when(() => platform.isMacOS).thenReturn(false);
          when(() => platform.isLinux).thenReturn(false);
        });

        group('when LocalAppData has a value', () {
          final androidStudioVersions = [
            'AndroidStudio',
            'AndroidStudio4.0',
            'AndroidStudio4.1',
            'AndroidStudio4.2',
            'AndroidStudio4.3',
          ];

          Directory setUpLocalAppData() {
            final tempDir = setUpAppTempDir();
            final googleDir = Directory(
              p.join(tempDir.path, 'Google'),
            )..createSync(recursive: true);

            for (final version in androidStudioVersions) {
              final androidStudioDir = Directory(
                p.join(googleDir.path, version),
              )..createSync(recursive: true);

              final installPath = p.join(tempDir.path, 'bin', version);
              if (version != androidStudioVersions.last) {
                // The last version should not have a .home file to test the
                // case where our highest versioned directory does not point to
                // a valid installation.
                Directory(installPath).createSync(recursive: true);
              }

              if (version != androidStudioVersions.first) {
                // Test the case where an Android Studio directory doesn't have
                // a .home file.

                File(
                  p.join(androidStudioDir.path, '.home'),
                )
                  ..createSync(recursive: true)
                  ..writeAsStringSync(installPath);
              }
            }

            return tempDir;
          }

          test('returns correct path', () async {
            final appDataDir = setUpLocalAppData();
            when(() => platform.environment).thenReturn(
              {'LOCALAPPDATA': appDataDir.path},
            );

            await expectLater(
              runWithOverrides(() => androidStudio.path),
              equals(p.join(appDataDir.path, 'bin', 'AndroidStudio4.2')),
            );
          });
        });

        group('when Local App Data has no value', () {
          test('returns correct path', () async {
            final tempDir = setUpAppTempDir();
            final androidStudioDir = Directory(
              p.join(tempDir.path, 'Android', 'Android Studio'),
            )..createSync(recursive: true);
            when(() => platform.environment).thenReturn({
              'PROGRAMFILES': tempDir.path,
              'PROGRAMFILES(X86)': tempDir.path,
            });
            await expectLater(
              runWithOverrides(() => androidStudio.path),
              equals(androidStudioDir.path),
            );
          });
        });
      });

      group('on MacOS', () {
        setUp(() {
          when(() => platform.isWindows).thenReturn(false);
          when(() => platform.isMacOS).thenReturn(true);
          when(() => platform.isLinux).thenReturn(false);
        });

        test('returns correct path', () async {
          final tempDir = setUpAppTempDir();
          final androidStudioDir = Directory(
            p.join(
              tempDir.path,
              'Applications',
              'Android Studio.app',
              'Contents',
            ),
          )..createSync(recursive: true);
          when(() => platform.environment).thenReturn({'HOME': tempDir.path});
          await expectLater(
            runWithOverrides(() => androidStudio.path),
            equals(androidStudioDir.path),
          );
        });
      });

      group('on Linux', () {
        setUp(() {
          when(() => platform.isWindows).thenReturn(false);
          when(() => platform.isMacOS).thenReturn(false);
          when(() => platform.isLinux).thenReturn(true);
        });

        test('returns correct path', () async {
          final tempDir = setUpAppTempDir();
          final androidStudioDir = Directory(
            p.join(tempDir.path, '.AndroidStudio'),
          )..createSync(recursive: true);
          when(() => platform.environment).thenReturn({'HOME': tempDir.path});
          await expectLater(
            runWithOverrides(() => androidStudio.path),
            equals(androidStudioDir.path),
          );
        });
      });
    });
  });
}

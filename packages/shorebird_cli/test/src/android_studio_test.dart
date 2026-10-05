import 'dart:io' hide Platform;

import 'package:path/path.dart' as p;
import 'package:platform/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:test/test.dart';

void main() {
  group(AndroidStudio, () {
    late TestNativePlatform platform;
    late AndroidStudio androidStudio;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {platformRef.overrideWith(() => platform)},
      );
    }

    Directory setUpAppTempDir() {
      final tempDir = Directory.systemTemp.createTempSync();
      Directory(p.join(tempDir.path, 'android')).createSync(recursive: true);
      return tempDir;
    }

    setUp(() {
      platform = TestNativePlatform();
      androidStudio = AndroidStudio();
    });

    group('path', () {
      group('on Windows', () {
        setUp(() {
          platform = platform.copyWith(operatingSystem: NativePlatform.windows);
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
            final googleDir = Directory(p.join(tempDir.path, 'Google'))
              ..createSync(recursive: true);

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

                File(p.join(androidStudioDir.path, '.home'))
                  ..createSync(recursive: true)
                  ..writeAsStringSync(installPath);
              }
            }

            return tempDir;
          }

          test('returns correct path', () async {
            final appDataDir = setUpLocalAppData();
            platform = platform.copyWith(
              environment: {'LOCALAPPDATA': appDataDir.path},
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
            platform = platform.copyWith(
              environment: {
                'PROGRAMFILES': tempDir.path,
                'PROGRAMFILES(X86)': tempDir.path,
              },
            );
            await expectLater(
              runWithOverrides(() => androidStudio.path),
              equals(androidStudioDir.path),
            );
          });
        });
      });

      group('on MacOS', () {
        setUp(() {
          platform = platform.copyWith(operatingSystem: NativePlatform.macOS);
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
          platform = platform.copyWith(environment: {'HOME': tempDir.path});
          await expectLater(
            runWithOverrides(() => androidStudio.path),
            equals(androidStudioDir.path),
          );
        });
      });

      group('on Linux', () {
        late Directory userHomeDir;

        setUp(() {
          platform = platform.copyWith(operatingSystem: NativePlatform.linux);

          userHomeDir = Directory.systemTemp.createTempSync();
          platform = platform.copyWith(environment: {'HOME': userHomeDir.path});
        });

        group('when installed at ~', () {
          late Directory androidStudioDir;

          setUp(() {
            androidStudioDir = Directory(
              p.join(userHomeDir.path, '.AndroidStudio'),
            )..createSync(recursive: true);
          });

          test('returns correct path', () async {
            await expectLater(
              runWithOverrides(() => androidStudio.path),
              equals(androidStudioDir.path),
            );
          });
        });

        group('when installed at ~/cache', () {
          late Directory androidStudioDir;

          setUp(() {
            androidStudioDir = Directory(
              p.join(userHomeDir.path, '.cache', 'Google', 'AndroidStudio'),
            )..createSync(recursive: true);
          });

          test('returns correct path', () async {
            await expectLater(
              runWithOverrides(() => androidStudio.path),
              equals(androidStudioDir.path),
            );
          });
        });

        group('when installed in JetBrains Toolbox apps directory', () {
          late Directory androidStudioDir;

          setUp(() {
            androidStudioDir = Directory(
              p.join(
                userHomeDir.path,
                '.local',
                'share',
                'JetBrains',
                'Toolbox',
                'apps',
                'AndroidStudio',
              ),
            )..createSync(recursive: true);
          });

          test('returns correct path', () async {
            await expectLater(
              runWithOverrides(() => androidStudio.path),
              equals(androidStudioDir.path),
            );
          });
        });
      });
    });
  });
}

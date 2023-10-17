import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(AndroidSdk, () {
    late Directory homeDirectory;
    late OperatingSystemInterface osInterface;
    late Platform platform;
    late AndroidSdk androidSdk;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          osInterfaceRef.overrideWith(() => osInterface),
          platformRef.overrideWith(() => platform),
        },
      );
    }

    String linuxAndroidHome() => p.join(homeDirectory.path, 'Android', 'Sdk');
    String macAndroidHome() =>
        p.join(homeDirectory.path, 'Library', 'Android', 'sdk');
    String windowsAndroidHome() => p.join(
          homeDirectory.path,
          'AppData',
          'Local',
          'Android',
          'Sdk',
        );

    void populateAndroidSdk({required String androidHomePath}) {
      Directory(p.join(androidHomePath, 'platform-tools'))
          .createSync(recursive: true);
    }

    File createAapt({
      required String androidHomePath,
      required bool isWindows,
    }) {
      Directory(p.join(androidHomePath, 'platform-tools')).createSync();
      return File(
        p.join(
          androidHomePath,
          'build-tools',
          '30.0.3',
          isWindows ? 'aapt.exe' : 'aapt',
        ),
      )..createSync(recursive: true);
    }

    File createAdb({required String androidHomePath, required bool isWindows}) {
      return File(
        p.join(
          androidHomePath,
          'platform-tools',
          isWindows ? 'adb.exe' : 'adb',
        ),
      )..createSync(recursive: true);
    }

    setUp(() {
      homeDirectory = Directory.systemTemp.createTempSync();
      osInterface = MockOperatingSystemInterface();
      platform = MockPlatform();
      androidSdk = AndroidSdk();

      when(() => osInterface.which(any())).thenReturn(null);
      when(() => platform.isLinux).thenReturn(false);
      when(() => platform.isMacOS).thenReturn(false);
      when(() => platform.isWindows).thenReturn(false);
      when(() => platform.environment).thenReturn({});
    });

    group('path', () {
      group('when ANDROID_HOME is set', () {
        setUp(() {
          when(() => platform.environment).thenReturn({
            kAndroidHome: homeDirectory.path,
          });
          populateAndroidSdk(androidHomePath: homeDirectory.path);
        });

        test('returns ANDROID_HOME', () {
          expect(runWithOverrides(() => androidSdk.path), homeDirectory.path);
        });
      });

      group('when ANDROID_SDK_ROOT is set', () {
        setUp(() {
          when(() => platform.environment).thenReturn({
            kAndroidSdkRoot: homeDirectory.path,
          });
          populateAndroidSdk(androidHomePath: homeDirectory.path);
        });

        test('returns ANDROID_SDK_ROOT', () {
          expect(runWithOverrides(() => androidSdk.path), homeDirectory.path);
        });
      });

      group("when checking the user's home directory", () {
        group('when the home directory exists', () {
          setUp(() {
            when(() => platform.environment).thenReturn({
              'HOME': homeDirectory.path,
              'USERPROFILE': homeDirectory.path,
            });
          });

          group('on Linux', () {
            setUp(() {
              when(() => platform.isLinux).thenReturn(true);
              populateAndroidSdk(androidHomePath: linuxAndroidHome());
            });

            test('returns android home', () {
              expect(
                runWithOverrides(() => androidSdk.path),
                equals(linuxAndroidHome()),
              );
            });
          });

          group('on macOS', () {
            setUp(() {
              when(() => platform.isMacOS).thenReturn(true);
              populateAndroidSdk(androidHomePath: macAndroidHome());
            });

            test('returns android home', () {
              expect(
                runWithOverrides(() => androidSdk.path),
                equals(macAndroidHome()),
              );
            });
          });

          group('on Windows', () {
            setUp(() {
              when(() => platform.isWindows).thenReturn(true);
              populateAndroidSdk(androidHomePath: windowsAndroidHome());
            });

            test('returns android home', () {
              expect(
                runWithOverrides(() => androidSdk.path),
                equals(windowsAndroidHome()),
              );
            });
          });
        });

        group("when the user's home directory doesn't exist", () {
          test('returns null', () {
            expect(runWithOverrides(() => androidSdk.path), isNull);
          });
        });
      });

      group("when aapt is on the user's path", () {
        group('when aapt is part of an Android SDK', () {
          setUp(() {
            final aapt = createAapt(
              androidHomePath: homeDirectory.path,
              isWindows: false,
            );
            when(() => osInterface.which('aapt')).thenReturn(aapt.path);
          });

          test('returns path to Android SDK', () {
            expect(
              runWithOverrides(() => androidSdk.path),
              equals(homeDirectory.resolveSymbolicLinksSync()),
            );
          });
        });

        group('when aapt is not in a valid Android SDK', () {
          setUp(() {
            when(() => osInterface.which('aapt'))
                .thenReturn(homeDirectory.path);
          });

          test('returns null', () {
            expect(runWithOverrides(() => androidSdk.path), isNull);
          });
        });
      });

      group("when adb is on the user's path", () {
        group('when adb is part of a valid Android SDK', () {
          setUp(() {
            final adb = createAdb(
              androidHomePath: homeDirectory.path,
              isWindows: false,
            );
            when(() => osInterface.which('adb')).thenReturn(adb.path);
          });

          test('returns path to Android SDK', () {
            expect(
              runWithOverrides(() => androidSdk.path),
              equals(homeDirectory.resolveSymbolicLinksSync()),
            );
          });
        });

        group('when adb is not part of a valid Android SDK', () {
          setUp(() {
            when(() => osInterface.which('adb')).thenReturn(homeDirectory.path);
          });

          test('returns null', () {
            expect(runWithOverrides(() => androidSdk.path), isNull);
          });
        });
      });

      group('when multiple Android SDK candidates are found', () {
        setUp(() {
          when(() => platform.isMacOS).thenReturn(true);

          // Add ANDROID_SDK_ROOT to path, but do not populate it.
          when(() => platform.environment).thenReturn({
            kAndroidSdkRoot: homeDirectory.path,
          });

          // Create a valid Android SDK in the user's home directory.
          when(() => platform.environment).thenReturn(
            {'HOME': homeDirectory.path},
          );
          populateAndroidSdk(androidHomePath: macAndroidHome());

          // Add adb to the path. This should not be returned, as the sdk in the
          // user's home directory should take precedence.
          final adb = createAdb(
            androidHomePath: homeDirectory.path,
            isWindows: false,
          );
          when(() => osInterface.which('adb')).thenReturn(adb.path);
        });

        test('returns the first valid candidate', () {
          expect(
            runWithOverrides(() => androidSdk.path),
            equals(macAndroidHome()),
          );
        });
      });

      group('when Android SDK is not found', () {
        test('returns null', () {
          expect(runWithOverrides(() => androidSdk.path), isNull);
        });
      });
    });

    group('adbPath', () {
      test('returns null when AndroidSdk is not available', () {
        expect(runWithOverrides(() => androidSdk.adbPath), isNull);
      });

      test('returns correct value on Linux', () async {
        when(() => platform.environment).thenReturn({
          kAndroidHome: homeDirectory.path,
        });
        when(() => platform.isLinux).thenReturn(true);
        populateAndroidSdk(androidHomePath: homeDirectory.path);
        final adb =
            createAdb(androidHomePath: homeDirectory.path, isWindows: false);
        expect(runWithOverrides(() => androidSdk.adbPath), adb.path);
      });

      test('returns correct value on MacOS', () async {
        when(() => platform.environment).thenReturn({
          kAndroidHome: homeDirectory.path,
        });
        when(() => platform.isMacOS).thenReturn(true);
        final adb = File(p.join(homeDirectory.path, 'platform-tools', 'adb'))
          ..createSync(recursive: true);
        expect(runWithOverrides(() => androidSdk.adbPath), adb.path);
      });

      test('returns correct value on Windows', () async {
        when(() => platform.environment).thenReturn({
          kAndroidHome: homeDirectory.path,
        });
        when(() => platform.isWindows).thenReturn(true);
        final adb = File(
          p.join(homeDirectory.path, 'platform-tools', 'adb.exe'),
        )..createSync(recursive: true);
        expect(runWithOverrides(() => androidSdk.adbPath), adb.path);
      });
    });
  });
}

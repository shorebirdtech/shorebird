import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/android_sdk.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:test/test.dart';

class _MockPlatform extends Mock implements Platform {}

void main() {
  group(AndroidSdk, () {
    late Directory homeDirectory;
    late Platform platform;
    late AndroidSdk androidSdk;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          platformRef.overrideWith(() => platform),
        },
      );
    }

    setUp(() {
      homeDirectory = Directory.systemTemp.createTempSync();
      platform = _MockPlatform();
      androidSdk = AndroidSdk();

      when(() => platform.isLinux).thenReturn(false);
      when(() => platform.isMacOS).thenReturn(false);
      when(() => platform.isWindows).thenReturn(false);
      when(() => platform.environment).thenReturn({});
    });

    group('path', () {
      test('returns null when env vars are not set', () {
        expect(runWithOverrides(() => androidSdk.path), isNull);
      });

      test('returns ANDROID_HOME when set', () {
        when(() => platform.environment).thenReturn({
          kAndroidHome: homeDirectory.path,
        });
        expect(
          runWithOverrides(() => androidSdk.path),
          equals(homeDirectory.path),
        );
      });

      test('returns ANDROID_SDK_ROOT when set', () {
        when(() => platform.environment).thenReturn({
          kAndroidSdkRoot: homeDirectory.path,
        });
        expect(
          runWithOverrides(() => androidSdk.path),
          equals(homeDirectory.path),
        );
      });

      test('returns null on Linux when HOME is not set', () {
        when(() => platform.isLinux).thenReturn(true);
        expect(
          runWithOverrides(() => androidSdk.path),
          isNull,
        );
      });

      test('returns correct path on Linux when HOME is set', () {
        when(() => platform.environment).thenReturn({
          'HOME': homeDirectory.path,
        });
        when(() => platform.isLinux).thenReturn(true);
        final androidHomeDir = Directory(
          p.join(homeDirectory.path, 'Android', 'Sdk'),
        )..createSync(recursive: true);
        expect(
          runWithOverrides(() => androidSdk.path),
          equals(androidHomeDir.path),
        );
      });

      test('returns null on MacOS when HOME is not set', () {
        when(() => platform.isMacOS).thenReturn(true);
        expect(
          runWithOverrides(() => androidSdk.path),
          isNull,
        );
      });

      test('returns correct path on MacOS', () {
        when(() => platform.environment).thenReturn({
          'HOME': homeDirectory.path,
        });
        when(() => platform.isMacOS).thenReturn(true);
        final androidHomeDir = Directory(
          p.join(homeDirectory.path, 'Library', 'Android', 'sdk'),
        )..createSync(recursive: true);
        expect(
          runWithOverrides(() => androidSdk.path),
          equals(androidHomeDir.path),
        );
      });

      test('returns null on Windows when USERPROFILE is not set', () {
        when(() => platform.isWindows).thenReturn(true);
        expect(
          runWithOverrides(() => androidSdk.path),
          isNull,
        );
      });

      test('returns correct path on Windows', () {
        when(() => platform.environment).thenReturn({
          'USERPROFILE': homeDirectory.path,
        });
        when(() => platform.isWindows).thenReturn(true);
        final androidHomeDir = Directory(
          p.join(homeDirectory.path, 'AppData', 'Local', 'Android', 'sdk'),
        )..createSync(recursive: true);
        expect(
          runWithOverrides(() => androidSdk.path),
          equals(androidHomeDir.path),
        );
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
        final adb = File(p.join(homeDirectory.path, 'cmdline-tools', 'adb'))
          ..createSync(recursive: true);
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

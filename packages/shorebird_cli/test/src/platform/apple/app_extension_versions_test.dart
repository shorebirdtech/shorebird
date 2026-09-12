import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/platform/apple/app_extension_versions.dart';
import 'package:shorebird_cli/src/platform/apple/plist.dart';
import 'package:test/test.dart';

void main() {
  group('findAppExtensionVersionMismatches', () {
    late Directory tempDir;
    late Directory appDirectory;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('app_extension_versions_');
      appDirectory = Directory(p.join(tempDir.path, 'Runner.app'))
        ..createSync(recursive: true);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    String plistContents({String? shortVersion, String? version}) {
      final entries = [
        if (shortVersion != null)
          '''
	<key>CFBundleShortVersionString</key>
	<string>$shortVersion</string>''',
        if (version != null)
          '''
	<key>CFBundleVersion</key>
	<string>$version</string>''',
      ].join('\n');

      return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
$entries
</dict>
</plist>
''';
    }

    void writeAppPlist({
      String? shortVersion = '1.0.0',
      String? version = '1',
    }) {
      File(p.join(appDirectory.path, 'Info.plist')).writeAsStringSync(
        plistContents(shortVersion: shortVersion, version: version),
      );
    }

    void writeExtension(
      String name, {
      String? shortVersion,
      String? version,
      String? rawContents,
      bool writePlist = true,
    }) {
      final extensionDirectory = Directory(
        p.join(appDirectory.path, 'PlugIns', name),
      )..createSync(recursive: true);
      if (!writePlist) return;
      File(p.join(extensionDirectory.path, 'Info.plist')).writeAsStringSync(
        rawContents ??
            plistContents(shortVersion: shortVersion, version: version),
      );
    }

    test('returns empty when the app has no Info.plist', () {
      writeExtension('Service.appex', shortVersion: '9.9.9', version: '99');

      expect(
        findAppExtensionVersionMismatches(appDirectory: appDirectory),
        isEmpty,
      );
    });

    test('returns empty when the app Info.plist is malformed', () {
      File(
        p.join(appDirectory.path, 'Info.plist'),
      ).writeAsStringSync('not a plist');
      writeExtension('Service.appex', shortVersion: '9.9.9', version: '99');

      expect(
        findAppExtensionVersionMismatches(appDirectory: appDirectory),
        isEmpty,
      );
    });

    test('returns empty when there is no PlugIns directory', () {
      writeAppPlist();

      expect(
        findAppExtensionVersionMismatches(appDirectory: appDirectory),
        isEmpty,
      );
    });

    test('returns empty when extension versions match', () {
      writeAppPlist();
      writeExtension('Service.appex', shortVersion: '1.0.0', version: '1');

      expect(
        findAppExtensionVersionMismatches(appDirectory: appDirectory),
        isEmpty,
      );
    });

    test('ignores non-.appex entries in PlugIns', () {
      writeAppPlist();
      final other = Directory(
        p.join(appDirectory.path, 'PlugIns', 'NotAnExtension.bundle'),
      )..createSync(recursive: true);
      File(
        p.join(other.path, 'Info.plist'),
      ).writeAsStringSync(plistContents(shortVersion: '9.9.9', version: '99'));

      expect(
        findAppExtensionVersionMismatches(appDirectory: appDirectory),
        isEmpty,
      );
    });

    test('skips extensions with no Info.plist', () {
      writeAppPlist();
      writeExtension('Service.appex', writePlist: false);

      expect(
        findAppExtensionVersionMismatches(appDirectory: appDirectory),
        isEmpty,
      );
    });

    test('skips extensions with a malformed Info.plist', () {
      writeAppPlist();
      writeExtension('Service.appex', rawContents: 'not a plist');

      expect(
        findAppExtensionVersionMismatches(appDirectory: appDirectory),
        isEmpty,
      );
    });

    test('skips keys the extension does not declare', () {
      writeAppPlist();
      // Declares a matching CFBundleVersion but no CFBundleShortVersionString.
      writeExtension('Service.appex', version: '1');

      expect(
        findAppExtensionVersionMismatches(appDirectory: appDirectory),
        isEmpty,
      );
    });

    test('reports a CFBundleShortVersionString mismatch', () {
      writeAppPlist(shortVersion: '1.15.67', version: '250');
      writeExtension(
        'NotificationService.appex',
        shortVersion: '1.15.32',
        version: '250',
      );

      final mismatches = findAppExtensionVersionMismatches(
        appDirectory: appDirectory,
      );

      expect(mismatches, hasLength(1));
      expect(mismatches.single.extensionName, 'NotificationService.appex');
      expect(mismatches.single.key, Plist.releaseVersionKey);
      expect(mismatches.single.appValue, '1.15.67');
      expect(mismatches.single.extensionValue, '1.15.32');
    });

    test('reports a CFBundleVersion mismatch', () {
      writeAppPlist(shortVersion: '1.15.67', version: '250');
      writeExtension(
        'NotificationService.appex',
        shortVersion: '1.15.67',
        version: '2142',
      );

      final mismatches = findAppExtensionVersionMismatches(
        appDirectory: appDirectory,
      );

      expect(mismatches, hasLength(1));
      expect(mismatches.single.key, Plist.buildNumberKey);
      expect(mismatches.single.appValue, '250');
      expect(mismatches.single.extensionValue, '2142');
    });

    test('reports both keys and multiple extensions, sorted by path', () {
      writeAppPlist(shortVersion: '3.50.0', version: '1719410970');
      writeExtension(
        'OneSignalNotificationService.appex',
        shortVersion: '1.0',
        version: '7',
      );
      writeExtension(
        'CleverTapNotificationService.appex',
        shortVersion: '1.0',
        version: '1',
      );

      final mismatches = findAppExtensionVersionMismatches(
        appDirectory: appDirectory,
      );

      expect(mismatches, hasLength(4));
      expect(
        mismatches.map((m) => '${m.extensionName}:${m.key}'),
        [
          'CleverTapNotificationService.appex:${Plist.releaseVersionKey}',
          'CleverTapNotificationService.appex:${Plist.buildNumberKey}',
          'OneSignalNotificationService.appex:${Plist.releaseVersionKey}',
          'OneSignalNotificationService.appex:${Plist.buildNumberKey}',
        ],
      );
    });
  });

  group('appExtensionVersionMismatchWarning', () {
    test('names each mismatch and how to fix it', () {
      final warning = appExtensionVersionMismatchWarning(const [
        AppExtensionVersionMismatch(
          extensionName: 'NotificationService.appex',
          key: Plist.releaseVersionKey,
          appValue: '1.15.67',
          extensionValue: '1.15.32',
        ),
      ]);

      expect(
        warning,
        allOf(
          contains('NotificationService.appex'),
          contains(Plist.releaseVersionKey),
          contains('1.15.67'),
          contains('1.15.32'),
          contains('ITMS-90473'),
          contains('MARKETING_VERSION'),
          contains('CURRENT_PROJECT_VERSION'),
        ),
      );
    });
  });
}

// cspell:words plutil
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/platform/apple/invalid_export_options_plist_exception.dart';
import 'package:shorebird_cli/src/platform/apple/plist.dart';
import 'package:test/test.dart';

void main() {
  group('Plist', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plist_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    group('constructor', () {
      test('throws PlistParseException when plist is malformed', () {
        final file = File(p.join(tempDir.path, 'Info.plist'))
          ..writeAsStringSync('not valid plist xml');

        expect(
          () => Plist(file: file),
          throwsA(
            isA<PlistParseException>()
                .having(
                  (e) => e.filePath,
                  'filePath',
                  file.path,
                )
                .having(
                  (e) => e.toString(),
                  'toString',
                  allOf(
                    contains('Failed to parse'),
                    contains('plutil -lint'),
                  ),
                ),
          ),
        );
      });
    });

    group('versionNumber', () {
      test('returns version from standard plist', () {
        final file = File(p.join(tempDir.path, 'Info.plist'))
          ..writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleShortVersionString</key>
	<string>1.2.3</string>
	<key>CFBundleVersion</key>
	<string>4</string>
</dict>
</plist>
''');

        expect(Plist(file: file).versionNumber, equals('1.2.3+4'));
      });

      test('returns version without build number when not present', () {
        final file = File(p.join(tempDir.path, 'Info.plist'))
          ..writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
</dict>
</plist>
''');

        expect(Plist(file: file).versionNumber, equals('1.0.0'));
      });

      test('throws when release version is missing', () {
        final file = File(p.join(tempDir.path, 'Info.plist'))
          ..writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleVersion</key>
	<string>1</string>
</dict>
</plist>
''');

        expect(
          () => Plist(file: file).versionNumber,
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Could not determine release version'),
            ),
          ),
        );
      });
    });
  });

  group('assertValidExportOptionsPlist', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('export_options_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    File writePlist(String body) {
      return File(p.join(tempDir.path, 'ExportOptions.plist'))
        ..writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
$body
</dict>
</plist>
''');
    }

    test('does not throw when file does not exist', () {
      final file = File(p.join(tempDir.path, 'missing.plist'));
      expect(() => assertValidExportOptionsPlist(file), returnsNormally);
    });

    test('does not throw when key is absent', () {
      final file = writePlist('<key>method</key><string>app-store</string>');
      expect(() => assertValidExportOptionsPlist(file), returnsNormally);
    });

    test('does not throw when key is false', () {
      final file = writePlist(
        '<key>manageAppVersionAndBuildNumber</key><false/>',
      );
      expect(() => assertValidExportOptionsPlist(file), returnsNormally);
    });

    test('throws InvalidExportOptionsPlistException when key is true', () {
      final file = writePlist(
        '<key>manageAppVersionAndBuildNumber</key><true/>',
      );
      expect(
        () => assertValidExportOptionsPlist(file),
        throwsA(
          isA<InvalidExportOptionsPlistException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('manageAppVersionAndBuildNumber'),
              contains('Patches will fail to apply'),
              contains('patch-not-showing-up'),
            ),
          ),
        ),
      );
    });

    test('propagates PlistParseException for malformed plist', () {
      final file = File(p.join(tempDir.path, 'ExportOptions.plist'))
        ..writeAsStringSync('not a plist');
      expect(
        () => assertValidExportOptionsPlist(file),
        throwsA(isA<PlistParseException>()),
      );
    });
  });
}

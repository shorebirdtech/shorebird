// cspell:words plutil
import 'dart:io';

import 'package:path/path.dart' as p;
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
}

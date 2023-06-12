import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:test/test.dart';

void main() {
  const xcodeWorkspaceName = 'Runner.xcworkspace';
  const archiveName = 'Runner.xcarchive';

  const versionedPlistContent = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ApplicationProperties</key>
	<dict>
		<key>CFBundleIdentifier</key>
		<string>com.shorebird.example</string>
		<key>CFBundleShortVersionString</key>
		<string>1.0.3</string>
		<key>CFBundleVersion</key>
		<string>10</string>
	</dict>
</dict>
</plist>''';

  const noVersionPlistContent = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ApplicationProperties</key>
	<dict>
		<key>CFBundleIdentifier</key>
		<string>com.shorebird.example</string>
	</dict>
</dict>
</plist>''';

  final workspacePath = p.join('ios', xcodeWorkspaceName);
  final archivePath = p.join('build', 'ios', 'archive', archiveName);

  Directory createTempDirectory({
    bool createWorkspace = true,
    bool createArchive = true,
    String? plistContent,
  }) {
    final tempDir = Directory.systemTemp.createTempSync();
    if (createWorkspace) {
      Directory(p.join(tempDir.path, workspacePath))
          .createSync(recursive: true);
    }

    if (createArchive) {
      Directory(p.join(tempDir.path, archivePath)).createSync(recursive: true);
    }

    if (plistContent != null) {
      File(p.join(tempDir.path, archivePath, 'Info.plist'))
        ..createSync(recursive: true)
        ..writeAsStringSync(plistContent);
    }
    return tempDir;
  }

  group(XcarchiveReader, () {
    test('creates Xcarchive', () async {
      final tempDir = createTempDirectory(plistContent: versionedPlistContent);

      final xcarchive = IOOverrides.runZoned(
        () => XcarchiveReader().xcarchiveFromProjectRoot(tempDir.path),
        getCurrentDirectory: () => tempDir,
      );

      expect(xcarchive.versionNumber, '1.0.3+10');
    });

    test('returns null if no xcworkspace exists', () {
      final tempDir = createTempDirectory(createWorkspace: false);
      expect(
        () => XcarchiveReader().xcarchiveFromProjectRoot(tempDir.path),
        throwsA(isA<Exception>()),
      );
    });

    test('throws exception if no xcarchive exists', () {
      final tempDir = createTempDirectory(createArchive: false);
      expect(
        () => XcarchiveReader().xcarchiveFromProjectRoot(tempDir.path),
        throwsA(isA<Exception>()),
      );
    });
  });

  group(Xcarchive, () {
    test('reads app version from xcarchive', () {
      final tempDir = createTempDirectory(plistContent: versionedPlistContent);
      final xcarchive = Xcarchive(path: p.join(tempDir.path, archivePath));
      expect(xcarchive.versionNumber, '1.0.3+10');
    });

    test('throws exception if no Info.plist is found', () {
      final tempDir = createTempDirectory();
      final xcarchive = Xcarchive(path: p.join(tempDir.path, archivePath));
      expect(() => xcarchive.versionNumber, throwsException);
    });

    test('throws exception if no version is found in Info.plist', () {
      final tempDir = createTempDirectory(plistContent: noVersionPlistContent);
      final xcarchive = Xcarchive(path: p.join(tempDir.path, archivePath));
      expect(() => xcarchive.versionNumber, throwsException);
    });
  });
}

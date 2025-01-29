import 'dart:io';

import 'package:shorebird_cli/src/platform/linux.dart';
import 'package:test/test.dart';

void main() {
  group('linux', () {
    group('versionFromLinuxBundle', () {
      late Directory bundleRoot;

      setUp(() {
        bundleRoot = Directory.systemTemp.createTempSync();
      });

      group('when json file does not exist', () {
        test('throws exception', () {
          expect(
            () => versionFromLinuxBundle(bundleRoot: bundleRoot),
            throwsA(
              isA<Exception>().having(
                (e) => '$e',
                'message',
                equals(
                  '''Exception: Version file not found in Linux bundle (expected at ${linuxBundleVersionFile(bundleRoot).path})''',
                ),
              ),
            ),
          );
        });
      });

      group('when json file exists', () {
        const jsonContent = '''
{
  "app_name": "linux_sandbox",
  "version": "1.0.0",
  "build_number": "9",
  "package_name": "linux_sandbox"
}
''';

        setUp(() {
          linuxBundleVersionFile(bundleRoot)
            ..createSync(recursive: true)
            ..writeAsStringSync(jsonContent);
        });

        test('returns expected version', () {
          expect(
            versionFromLinuxBundle(bundleRoot: bundleRoot),
            equals('1.0.0+9'),
          );
        });
      });
    });
  });
}

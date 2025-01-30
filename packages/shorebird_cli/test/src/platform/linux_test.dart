import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/platform/linux.dart';
import 'package:test/test.dart';

void main() {
  group('linux', () {
    group('minimumSupportedLinuxFlutterVersion', () {
      test('is 3.27.3', () {
        expect(
          minimumSupportedLinuxFlutterVersion,
          equals(Version(3, 27, 3)),
        );
      });
    });

    group('versionFromLinuxBundle', () {
      late Directory bundleRoot;
      late Linux linux;

      setUp(() {
        bundleRoot = Directory.systemTemp.createTempSync();
        linux = Linux();
      });

      group('when json file does not exist', () {
        test('throws exception', () {
          expect(
            () => linux.versionFromLinuxBundle(bundleRoot: bundleRoot),
            throwsA(
              isA<Exception>().having(
                (e) => '$e',
                'message',
                equals(
                  '''Exception: Version file not found in Linux bundle (expected at ${linux.linuxBundleVersionFile(bundleRoot).path})''',
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
          linux.linuxBundleVersionFile(bundleRoot)
            ..createSync(recursive: true)
            ..writeAsStringSync(jsonContent);
        });

        test('returns expected version', () {
          expect(
            linux.versionFromLinuxBundle(bundleRoot: bundleRoot),
            equals('1.0.0+9'),
          );
        });
      });
    });
  });
}

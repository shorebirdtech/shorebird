import 'dart:io';

import 'package:path/path.dart' as p;
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
        test('returns null', () {
          expect(versionFromLinuxBundle(bundleRoot: bundleRoot), isNull);
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
          File(
            p.join(
              bundleRoot.path,
              'data',
              'flutter_assets',
              'version.json',
            ),
          )
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

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/mf_reader.dart';
import 'package:test/test.dart';

void main() {
  group(MfReader, () {
    const fileContent = '''
Manifest-Version: 1.0
Built-By: Signflinger
Created-By: Signflinger

Name: BUNDLE-METADATA/com.android.tools.build.gradle/app-metadata.prop
 erties
SHA-256-Digest: Y9a0mKIrJP9ygajC+nXOu9HRrHGFilTiRYHA5x3cZRs=

Name: BUNDLE-METADATA/com.android.tools.build.libraries/dependencies.p
 b
SHA-256-Digest: b23DKN21/V4M5TUGFR9G37D30i886zSRJ93jFr8hEfQ=

Name: BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map
SHA-256-Digest: pJO/g5sJghLBCx1iv55JLFRgrYHQF9blCp3j/sIpv/s=

Name: base/assets/flutter_assets/shorebird.yaml
SHA-256-Digest: WkS2WF7aQZuQ91vLhCXq0vXjRx702kn5K6nAYwQiDec=

Name: base/dex/classes.dex
SHA-256-Digest: wCxl8B3GnKZdBjEOIaW/AhLmIQYXIlYwVC9VRisYGsw=''';

    final expectedPathHashes = {
      'BUNDLE-METADATA/com.android.tools.build.gradle/app-metadata.properties':
          'Y9a0mKIrJP9ygajC+nXOu9HRrHGFilTiRYHA5x3cZRs=',
      'BUNDLE-METADATA/com.android.tools.build.libraries/dependencies.pb':
          'b23DKN21/V4M5TUGFR9G37D30i886zSRJ93jFr8hEfQ=',
      'BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map':
          'pJO/g5sJghLBCx1iv55JLFRgrYHQF9blCp3j/sIpv/s=',
      'base/assets/flutter_assets/shorebird.yaml':
          'WkS2WF7aQZuQ91vLhCXq0vXjRx702kn5K6nAYwQiDec=',
      'base/dex/classes.dex': 'wCxl8B3GnKZdBjEOIaW/AhLmIQYXIlYwVC9VRisYGsw=',
    };

    test('parses content string into MfEntry list', () {
      final entries = MfReader.parse(fileContent);
      expect(entries, expectedPathHashes);
    });

    test('parses file contents into MfEntry list', () {
      final tempDir = Directory.systemTemp.createTempSync();
      final file = File(p.join(tempDir.path, 'MANIFEST.MF'))
        ..writeAsStringSync(fileContent);
      final entries = MfReader.read(file);
      expect(entries, expectedPathHashes);
    });
  });
}

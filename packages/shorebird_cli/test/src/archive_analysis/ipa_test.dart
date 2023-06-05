import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:test/test.dart';

void main() {
  final ipaFixturesBasePath = p.join('test', 'fixtures', 'ipas');
  final baseIpaBath = p.join(ipaFixturesBasePath, 'base.ipa');

  group(Ipa, () {
    test('reads app version from ipa', () {
      final ipa = Ipa(path: baseIpaBath);
      expect(ipa.versionNumber, '1.0.0');
    });
  });
}

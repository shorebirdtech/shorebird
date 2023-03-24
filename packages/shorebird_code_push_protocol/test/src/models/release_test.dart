import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Release', () {
    test('can be (de)serialized', () {
      const release = Release(
        id: 1,
        appId: 'app-id',
        version: '1.0.0',
        displayName: 'v1.0.0',
      );
      expect(
        Release.fromJson(release.toJson()).toJson(),
        equals(release.toJson()),
      );
    });
  });
}

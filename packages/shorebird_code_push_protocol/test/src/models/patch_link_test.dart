import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(PatchLink, () {
    test('can be (de)serialized when linked', () {
      const link = PatchLink(
        result: 'linked',
        platforms: ['ios'],
      );
      final json = link.toJson();
      expect(json['platforms'], equals(['ios']));
      expect(PatchLink.fromJson(json), equals(link));
    });

    test('can be (de)serialized when not linked', () {
      const link = PatchLink(
        result: 'not_linked',
        reason: 'platform_has_newer_patch',
        linkNumber: 7,
        platformPatchNumber: 8,
      );
      expect(PatchLink.fromJson(link.toJson()), equals(link));
    });

    test('reads a platform this client does not know', () {
      final link = PatchLink.fromJson(const {
        'result': 'linked',
        'platforms': ['web'],
      });
      expect(link.platforms, equals(['web']));
    });
  });
}

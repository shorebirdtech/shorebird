import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ReleasePatch, () {
    test('is equatable', () {
      expect(
        // Ignoring const constructor for equality comparison.
        const ReleasePatch(
          id: 0,
          number: 1,
          channel: 'channel',
          isRolledBack: false,
          artifacts: [],
        ),
        equals(
          // Ignoring const constructor for equality comparison.
          const ReleasePatch(
            id: 0,
            number: 1,
            channel: 'channel',
            isRolledBack: false,
            artifacts: [],
          ),
        ),
      );
    });

    test('round-trips a clientPatchId', () {
      const patch = ReleasePatch(
        id: 0,
        number: 1,
        channel: 'channel',
        isRolledBack: false,
        artifacts: [],
        clientPatchId: 'abc1234',
      );
      final json = patch.toJson();
      expect(json['client_patch_id'], equals('abc1234'));
      expect(ReleasePatch.fromJson(json).clientPatchId, equals('abc1234'));
    });

    test('parses json without client_patch_id', () {
      final patch = ReleasePatch.fromJson(const {
        'id': 0,
        'number': 1,
        'channel': 'channel',
        'is_rolled_back': false,
        'artifacts': <Map<String, dynamic>>[],
      });
      expect(patch.clientPatchId, isNull);
    });

    test('toJson always includes client_patch_id (null when unset)', () {
      const patch = ReleasePatch(
        id: 0,
        number: 1,
        channel: 'channel',
        isRolledBack: false,
        artifacts: [],
      );
      final json = patch.toJson();
      expect(json.containsKey('client_patch_id'), isTrue);
      expect(json['client_patch_id'], isNull);
    });

    test('clientPatchId participates in equality', () {
      final a = ReleasePatch.fromJson(const {
        'id': 0,
        'number': 1,
        'channel': 'channel',
        'is_rolled_back': false,
        'artifacts': <Map<String, dynamic>>[],
        'client_patch_id': 'abc',
      });
      final b = ReleasePatch.fromJson(const {
        'id': 0,
        'number': 1,
        'channel': 'channel',
        'is_rolled_back': false,
        'artifacts': <Map<String, dynamic>>[],
        'client_patch_id': 'abc',
      });
      final c = ReleasePatch.fromJson(const {
        'id': 0,
        'number': 1,
        'channel': 'channel',
        'is_rolled_back': false,
        'artifacts': <Map<String, dynamic>>[],
        'client_patch_id': 'xyz',
      });
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}

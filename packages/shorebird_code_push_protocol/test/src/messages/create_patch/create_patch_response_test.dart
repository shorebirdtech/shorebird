import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreatePatchResponse, () {
    test('round-trips a clientPatchId', () {
      const response = CreatePatchResponse(
        id: 1,
        number: 2,
        clientPatchId: 'abc1234',
      );
      final json = response.toJson();
      expect(json['client_patch_id'], equals('abc1234'));
      expect(
        CreatePatchResponse.fromJson(json).clientPatchId,
        equals('abc1234'),
      );
    });

    test('parses json without client_patch_id', () {
      final response = CreatePatchResponse.fromJson(const {
        'id': 1,
        'number': 2,
      });
      expect(response.clientPatchId, isNull);
    });

    test('toJson always includes client_patch_id (null when unset)', () {
      const response = CreatePatchResponse(id: 1, number: 2);
      final json = response.toJson();
      expect(json.containsKey('client_patch_id'), isTrue);
      expect(json['client_patch_id'], isNull);
    });

    test('clientPatchId participates in equality', () {
      final a = CreatePatchResponse.fromJson(const {
        'id': 1,
        'number': 2,
        'client_patch_id': 'abc',
      });
      final b = CreatePatchResponse.fromJson(const {
        'id': 1,
        'number': 2,
        'client_patch_id': 'abc',
      });
      final c = CreatePatchResponse.fromJson(const {
        'id': 1,
        'number': 2,
        'client_patch_id': 'xyz',
      });
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('round-trips channel', () {
      const response = CreatePatchResponse(
        id: 1,
        number: 2,
        channel: 'stable',
      );
      final json = response.toJson();
      expect(json['channel'], equals('stable'));
      expect(CreatePatchResponse.fromJson(json).channel, equals('stable'));
    });

    test('parses json without channel', () {
      final response = CreatePatchResponse.fromJson(const {
        'id': 1,
        'number': 2,
      });
      expect(response.channel, isNull);
    });

    test('toJson always includes channel (null when unset)', () {
      const response = CreatePatchResponse(id: 1, number: 2);
      final json = response.toJson();
      expect(json.containsKey('channel'), isTrue);
      expect(json['channel'], isNull);
    });

    test('channel participates in equality', () {
      const a = CreatePatchResponse(id: 1, number: 2, channel: 'stable');
      const b = CreatePatchResponse(id: 1, number: 2, channel: 'stable');
      const c = CreatePatchResponse(id: 1, number: 2, channel: 'staging');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}

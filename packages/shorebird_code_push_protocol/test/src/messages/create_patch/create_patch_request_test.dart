import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreatePatchRequest, () {
    test('can be (de)serialized', () {
      const request = CreatePatchRequest(
        releaseId: 1234,
        metadata: {'foo': 'bar'},
      );
      expect(
        CreatePatchRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });

    test('round-trips a clientPatchId', () {
      const request = CreatePatchRequest(
        releaseId: 1234,
        metadata: {'foo': 'bar'},
        clientPatchId: 'abc1234',
      );
      final json = request.toJson();
      expect(json['client_patch_id'], equals('abc1234'));
      expect(
        CreatePatchRequest.fromJson(json).clientPatchId,
        equals('abc1234'),
      );
    });

    test('parses json without client_patch_id', () {
      final request = CreatePatchRequest.fromJson(const {
        'release_id': 1234,
        'metadata': {'foo': 'bar'},
      });
      expect(request.clientPatchId, isNull);
    });

    test('toJson always includes client_patch_id (null when unset)', () {
      const request = CreatePatchRequest(
        releaseId: 1234,
        metadata: {'foo': 'bar'},
      );
      final json = request.toJson();
      expect(json.containsKey('client_patch_id'), isTrue);
      expect(json['client_patch_id'], isNull);
    });

    test('clientPatchId participates in equality', () {
      final a = CreatePatchRequest.fromJson(const {
        'release_id': 1234,
        'metadata': {'foo': 'bar'},
        'client_patch_id': 'abc',
      });
      final b = CreatePatchRequest.fromJson(const {
        'release_id': 1234,
        'metadata': {'foo': 'bar'},
        'client_patch_id': 'abc',
      });
      final c = CreatePatchRequest.fromJson(const {
        'release_id': 1234,
        'metadata': {'foo': 'bar'},
        'client_patch_id': 'xyz',
      });
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}

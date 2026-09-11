import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(PendingRelease, () {
    test('can be (de)serialized', () {
      final pending = PendingRelease(
        id: 537,
        version: '1.2.4+6',
        createdAt: DateTime(2024),
      );
      expect(
        PendingRelease.fromJson(pending.toJson()).toJson(),
        equals(pending.toJson()),
      );
    });
  });
}

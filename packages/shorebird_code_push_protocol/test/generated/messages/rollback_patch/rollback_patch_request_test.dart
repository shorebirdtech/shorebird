// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('RollbackPatchRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = RollbackPatchRequest();
      final parsed = RollbackPatchRequest.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(RollbackPatchRequest.maybeFromJson(null), isNull);
    });
  });
}

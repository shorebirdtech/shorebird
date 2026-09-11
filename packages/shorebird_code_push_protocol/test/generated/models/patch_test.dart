// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Patch', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = Patch(id: 0, number: 0);
      final parsed = Patch.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(Patch.maybeFromJson(null), isNull);
    });
  });
}

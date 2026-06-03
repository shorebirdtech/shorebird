// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PatchAdoptionRange', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = PatchAdoptionRange(
        start: DateTime.utc(2024),
        end: DateTime.utc(2024),
      );
      final parsed = PatchAdoptionRange.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(PatchAdoptionRange.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => PatchAdoptionRange.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}

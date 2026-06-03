// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PatchAdoptionPoint', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = PatchAdoptionPoint(
        period: DateTime.utc(2024),
        devices: 0,
        target: 0,
        adoptionPct: 0,
      );
      final parsed = PatchAdoptionPoint.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(PatchAdoptionPoint.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => PatchAdoptionPoint.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}

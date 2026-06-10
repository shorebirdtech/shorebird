// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ActiveHourEntry', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = ActiveHourEntry(hourUtc: 0, averageActiveDevices: 0);
      final parsed = ActiveHourEntry.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ActiveHourEntry.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => ActiveHourEntry.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}

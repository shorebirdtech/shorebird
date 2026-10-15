// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PatchMetricBreakdownEntry', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = PatchMetricBreakdownEntry(
        groupBy: 'example',
        groupValue: 'example',
        count: 0,
      );
      final parsed = PatchMetricBreakdownEntry.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(PatchMetricBreakdownEntry.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => PatchMetricBreakdownEntry.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
